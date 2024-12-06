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
  # Do it this way because the reboot task/plan (puppetlabs/reboot) do not support ifneeded
  # though by using an apply, we will have to parse result for expected errors ie: apply will fail due to the node rebooting
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

  $pre_reboot_success = $pre_reboot_resultset.ok_set
  $pre_reboot_success_ran = $pre_reboot_success.filter |$items| {
    'Reboot[Growell_patch - Pre Patch Reboot]' in $items['value']['report']['resource_statuses'] and $items['value']['report']['resource_statuses']['Reboot[Growell_patch - Pre Patch Reboot]']['changed'] == true
  }

  ## DEBUG
  out::message($pre_reboot_success)
  out::message($pre_reboot_sucess_ran)

  # basic output
  $pre_reboot_resultset.each |$result| {
    out::message($result.report)
  }

  # wait 5 sec so the reboot hopefully takes hold
  ctrl::sleep(5)

  # using the reboot plan would avoid having to do this, and likely do a better job at handling
  $pre_reboot_wait_resultset = wait_until_available(
    $targets,
    wait_time      => 120,
    retry_interval => 1,
    _catch_errors  => true,
  )

  # basic output
  $pre_reboot_wait_resultset.each |$result| {
    out::message($result)
  }

  # Pre Checks
  # Pre Patching Scripts (if they exist)
  # Main Patching Process
  $patch_resultset = apply(
    $targets,
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

  # Post Reboot (yes, no, if needed)
  # Do it this way because the reboot task/plan (puppetlabs/reboot) do not support ifneeded
  # though by using an apply, we will have to parse result for expected errors ie: apply will fail due to the node rebooting
  $post_reboot_resultset = apply(
    $targets,
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

  # wait 5 sec so the reboot hopefully takes hold
  ctrl::sleep(5)

  # using the reboot plan would avoid having to do this, and likely do a better job at handling
  $post_reboot_wait_resultset = wait_until_available(
    $targets,
    wait_time      => 120,
    retry_interval => 1,
    _catch_errors  => true,
  )

  # basic output
  $post_reboot_wait_resultset.each |$result| {
    out::message($result)
  }

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
