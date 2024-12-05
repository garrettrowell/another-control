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
        $report_script_loc = "/opt/puppetlabs/${module_name}/reporting.rb"
        $report_script_file = $report_script_loc
      }
      'windows': {
        $report_script_file = "C:/ProgramData/PuppetLabs/${module_name}/reporting.rb"
        $report_script_loc = "\"C:/Program Files/Puppet Labs/Puppet/puppet/bin/ruby.exe\" ${report_script_file}"
      }
    }
    class { 'growell_patch::pre_reboot':
      reboot_type       => $pre_reboot,
      priority          => 'normal',
      report_script_loc => $report_script_loc,
    }
  }

  # using the reboot plan would avoid having to do this, and likely do a better job at handling
  $pre_reboot_wait_resultset = wait_until_available(
    $targets,
    wait_time      => 120,
    retry_interval => 1,
    _catch_errors  => true,
  )

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
        $report_script_loc = "/opt/puppetlabs/${module_name}/reporting.rb"
        $report_script_file = $report_script_loc
      }
      'windows': {
        $report_script_file = "C:/ProgramData/PuppetLabs/${module_name}/reporting.rb"
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
      report_script_loc => $report_script_loc,
    }
  }

  # using the reboot plan would avoid having to do this, and likely do a better job at handling
  $post_reboot_wait_resultset = wait_until_available(
    $targets,
    wait_time      => 120,
    retry_interval => 1,
    _catch_errors  => true,
  )

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
  $pre_reboot_resultset.each |$result| {
    out::message($result.report)
  }
  $pre_reboot_wait_resultset.each |$result| {
    out::message($result)
  }
  $patch_resultset.each |$result| {
    out::message($result.report)
  }
  $post_reboot_resultset.each |$result| {
    out::message($result.report)
  }
  $post_reboot_wait_resultset.each |$result| {
    out::message($result)
  }
  $post_patch_resultset.each |$result| {
    out::message($result.report)
  }


}
