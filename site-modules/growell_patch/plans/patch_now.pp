plan growell_patch::patch_now(
  TargetSpec $targets,
  Optional[Enum['always', 'never', 'ifneeded']] $pre_reboot = 'always',
  Optional[Enum['always', 'never', 'ifneeded']] $post_reboot = 'always',
) {
  # collect facts
  run_plan(
    'facts',
    'targets' => $targets,
    '_catch_errors' => true
  )

  # DEBUG
  # print out facts for each target
  get_targets($targets).each |$t| {
    out::message($t.facts)
  }

  # So we can detect when a node has rebooted
  # Lifted from pe_patch::group_patching
  $begin_boot_time_results = without_default_logging() || {
    run_task('pe_patch::last_boot_time', $targets, '_catch_errors' => true)
  }

  $begin_boot_time_target_info = Hash($begin_boot_time_results.results.map |$item| {
    [$item.target.name, $item.message]
  })

  ## DEBUG
  out::message($begin_boot_time_target_info)

  # Pre Reboot (yes, no, if needed)
  $pre_reboot_resultset = apply(
    $targets,
    '_description'  => 'Pre Reboot',
    '_catch_errors' => true,
  ) {
    # there's gotta be a better way than copy/pasting this from init.pp
    case $facts['kernel'].downcase {
      'linux': {
        $report_script_loc = "/opt/puppetlabs/growell_patch/reporting.rb"
        $report_script_file = $report_script_loc
      }
      'windows': {
        $report_script_file = "C:/ProgramData/PuppetLabs/growell_patch/reporting.rb"
        $report_script_loc = "\"C:/Program Files/Puppet Labs/Puppet/puppet/bin/ruby.exe\" ${report_script_file}"
      }
    }
    class { 'growell_patch::pre_reboot':
      reboot_type       => $pre_reboot,
      reboot_delay      => 0,
      priority          => 'normal',
      run_as_plan       => true,
      report_script_loc => $report_script_loc,
    }
  }

  # Determine which nodes should be rebooting
  $pre_reboot_initiated = $pre_reboot_resultset.ok_set.to_data.filter |$index, $vals| {
    'Reboot[Growell_patch - Pre Patch Reboot]' in $vals['value']['report']['resource_statuses'].keys and $vals['value']['report']['resource_statuses']['Reboot[Growell_patch - Pre Patch Reboot]']['changed'] == true
  }

  # If the pre_reboot apply succeeds but the resources are not in the catalog, go ahead and continue with the process
  if $pre_reboot_initiated.empty {
    $patching_ready = $pre_reboot_resultset.ok_set.names
  } else {
    $pre_reboot_wait_results = run_plan(
      'pe_patch::wait_for_reboot',
      target_info      => $begin_boot_time_target_info,
      reboot_wait_time => 600,
    )
    $pre_reboot_timed_out = $pre_reboot_wait_results['pending']
    $patching_ready = $pre_reboot_resultset.ok_set.names - $pre_reboot_timed_out
  }

  # basic output
  $pre_reboot_resultset.each |$result| {
    out::message($result.report)
  }
  ## DEBUG
  out::message("patching_ready: ${patching_ready}")

  # So we can detect when a node has rebooted again
  # Lifted from pe_patch::group_patching
  $middle_boot_time_results = without_default_logging() || {
    run_task('pe_patch::last_boot_time', $patching_ready, '_catch_errors' => true)
  }

  $middle_boot_time_target_info = Hash($middle_boot_time_results.results.map |$item| {
    [$item.target.name, $item.message]
  })


  # Pre Checks
  # Pre Patching Scripts (if they exist)
  # Main Patching Process
  $patch_resultset = apply(
    $patching_ready,
    '_description' => 'Main Patching Run',
    '_catch_errors' => true
  ) {
    class { 'growell_patch':
      patch_group => 'always',
      run_as_plan => true,
    }
  }

  # basic output
  $patch_resultset.each |$result| {
    out::message($result.report)
  }

  # Determine for which nodes the pre_patching script (if it exists) ran successfully
  # This exec only fires if the script was successful
  $pre_patching_script_success = $patch_resultset.ok_set.filter_set |$vals| {
    'Exec[Growell_patch - Pre Patching Script - success]' in $vals.to_data['value']['report']['resource_statuses'].keys
  }
  # Determine for which nodes the pre_check ran successfully
  # This exec only fires if the pre_check was successful
  $pre_check_success = $patch_resultset.ok_set.filter_set |$vals| {
    'Exec[Growell_patch - Pre Check - success]' in $vals.to_data['value']['report']['resource_statuses'].keys
  }
  # Determine if all updates installed correctly, or if any failed, or if there simply were none
  # When all updates installed correctly, or there were none, any pre_patching script was successful as well as the pre_check
  $patch_status = $patch_resultset.to_data.reduce({'patch_success' => [], 'patch_failed' => [], 'nothing_to_patch' => []}) |$memo, $node| {
    $resources = $node['value']['report']['resource_statuses']
    $failed_packages = $resources.filter |$k, $v| {
      ($v['resource_type'] == 'Package') and ('patchday' in $v['tags']) and ($v['failed'] == true)
    }
    $installed_packages = $resources.filter |$k, $v| {
      ($v['resource_type'] == 'Package') and ('patchday' in $v['tags']) and ($v['failed'] == false)
    }

    if $failed_packages.keys.count > 0 {
      $patch_failed_memo = $memo['patch_failed'] + $node['target']
      $patch_success_memo = $memo['patch_success']
      $nothing_to_patch_memo = $memo['nothing_to_patch']
    } elsif $installed_packages.keys.count > 0 and $failed_packages.keys.empty {
      $patch_failed_memo = $memo['patch_failed']
      $patch_success_memo = $memo['patch_success'] + $node['target']
      $nothing_to_patch_memo = $memo['nothing_to_patch']
    } elsif $installed_packages.keys.count.empty and $failed_packages.keys.empty {
      $nothing_to_patch_memo = $memo['nothing_to_patch'] + $node['target']
      $patch_failed_memo = $memo['patch_failed']
      $patch_success_memo = $memo['patch_success']
    }

    ({
      'patch_success' => $patch_success_memo,
      'patch_failed' => $patch_failed_memo,
      'nothing_to_patch' => $nothing_to_patch_memo,
    })
  }

  out::message("pre_patch_script_success: ${pre_patching_script_success.names}")
  out::message("pre_check_success: ${pre_check_success.names}")
  out::message("patch_status: ${patch_status}")

  # Post Reboot (yes, no, if needed)
  # Do it this way because the reboot task/plan (puppetlabs/reboot) do not support ifneeded
  # though by using an apply, we will have to parse result for expected errors ie: apply will fail due to the node rebooting
  $post_reboot_resultset = apply(
    $patch_status['patch_success'] + $patch_status['nothing_to_patch'],
    '_description'  => 'Post Reboot',
    '_catch_errors' => true,
  ) {
    # there's gotta be a better way than copy/pasting this from init.pp
    case $facts['kernel'].downcase {
      'linux': {
        $report_script_loc = "/opt/puppetlabs/growell_patch/reporting.rb"
        $report_script_file = $report_script_loc
      }
      'windows': {
        $report_script_file = "C:/ProgramData/PuppetLabs/growell_patch/reporting.rb"
        $report_script_loc = "\"C:/Program Files/Puppet Labs/Puppet/puppet/bin/ruby.exe\" ${report_script_file}"
      }
    }

    # again another copy/paste from init.pp
    $_post_reboot = case $post_reboot {
      'always': { true }
      'never': { false }
      'ifneeded': { true }
      default: { false }
    }
    class { 'growell_patch::reboot':
      reboot_if_needed  => $_post_reboot,
      reboot_delay      => 0,
      run_as_plan       => true,
      report_script_loc => $report_script_loc,
    }
  }

  # basic output
  $post_reboot_resultset.each |$result| {
    out::message($result.report)
  }

  # Determine which nodes should be rebooting
  $post_reboot_initiated = $post_reboot_resultset.ok_set.to_data.filter |$index, $vals| {
    'Reboot[Growell_patch - Patch Reboot]' in $vals['value']['report']['resource_statuses'].keys and $vals['value']['report']['resource_statuses']['Reboot[Growell_patch - Patch Reboot]']['changed'] == true
  }

  # If the post_reboot apply succeeds but the resources are not in the catalog, go ahead and continue with the process
  if $post_reboot_initiated.empty {
    $patching_ready = $post_reboot_resultset.ok_set.names
  } else {
    $post_reboot_wait_results = run_plan(
      'pe_patch::wait_for_reboot',
      target_info      => $middle_boot_time_target_info,
      reboot_wait_time => 600,
    )
    $post_reboot_timed_out = $post_reboot_wait_results['pending']
    $patching_ready = $post_reboot_resultset.ok_set.names - $post_reboot_timed_out
  }

  #  # wait 5 sec so the reboot hopefully takes hold
  #  ctrl::sleep(5)
  #
  #  # using the reboot plan would avoid having to do this, and likely do a better job at handling
  #  $post_reboot_wait_resultset = wait_until_available(
  #    $targets,
  #    wait_time      => 120,
  #    retry_interval => 1,
  #    _catch_errors  => true,
  #  )
  #
  #  # basic output
  #  $post_reboot_wait_resultset.each |$result| {
  #    out::message($result)
  #  }

  # re-collect facts to pickup changes in patching facts
  run_plan(
    'facts',
    'targets' => $targets,
    '_catch_errors' => true
  )

  # DEBUG
  # print out facts for each target
  get_targets($targets).each |$t| {
    out::message($t.facts)
  }

  # Post Checks
  # Post Patching Scripts (if they exist)
  $post_patch_resultset = apply(
    $targets,
    '_description' => 'Post Patching Validation',
    '_catch_errors' => true
  ) {
    class { 'growell_patch':
      patch_group => 'always',
      run_as_plan => true,
    }
  }

  # basic output
  $post_patch_resultset.each |$result| {
    out::message($result.report)
  }


}
