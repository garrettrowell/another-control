class growell_patch::pre_patch_script (
  Enum['normal','high'] $priority = 'normal',
  Hash $pre_patch_commands,
  String $report_script_loc,
){
  case $priority {
    'normal': {
      $_schedule = 'Growell_patch - Patch Window'
      $_exec_title_base = "Growell_patch - Before patching - "
      $_notify_title_base = "Growell_patch - Pre Patching Script"
    }
    'high': {
      $_schedule = 'Growell_patch - High Priority Patch Window'
      $_exec_title_base = "Growell_patch - Before patching (High Priority) - "
      $_notify_title_base = "Growell_patch - Pre Patching Script (High Priority)"
    }
  }

  if $facts['growell_patch_report'].dig('pre_patching_script') {
    $cur = growell_patch::within_cur_month($facts['growell_patch_report']['pre_patching_script']['timestamp'])
    if $cur {
      if $facts['growell_patch_report']['pre_patching_script']['status'] == 'success' {
        $_needs_ran = Timestamp.new() < Timestamp($facts['growell_patch_report']['pre_patching_script']['timestamp'])
      } else {
        $_needs_ran = true
      }
    } else {
      $_needs_ran = true
    }
  } else {
    $_needs_ran = true
  }

  if $_needs_ran {
    # Initially record that the post patch script failed
    $failure_data = stdlib::to_json(
      {
        'pre_patching_script' => {
          'status' => 'failed',
          'timestamp' => Timestamp.new()
        }
      }
    )
    exec { "${_notify_title_base} - failed":
      command     => "${report_script_loc} -d '${failure_data}'",
      schedule    => $_schedule,
    }

    # Run the post_patch_command(s)
    $pre_patch_commands.each |$cmd, $cmd_opts| {
      exec { "${_exec_title_base}${cmd}":
        *        => delete($cmd_opts, ['require', 'before', 'schedule', 'tag']),
        require  => Exec["${_notify_title_base} - failed"],
        before   => Class["${module_name}::${facts['kernel'].downcase}::patchday"],
        schedule => $_schedule,
        notify   => Exec["${_notify_title_base} - success"],
        tag      => ['growell_patch_pre_patching', "${module_name}_pre_script"],
      }
    }

    # In the event the post patch script(s) fail, this resource will get skipped
    $success_data = stdlib::to_json(
      {
        'pre_patching_script' => {
          'status' => 'success',
          'timestamp' => Timestamp.new()
        }
      }
    )
    exec { "${_notify_title_base} - success":
      command     => "${report_script_loc} -d '${success_data}'",
      refreshonly => true,
      schedule    => $_schedule,
    }
  }

  # Make sure pre checks happen before any pre patch script
  Exec <| tag == "${module_name}_pre_check" |> -> Exec <| tag == "${module_name}_pre_script" |>
}
