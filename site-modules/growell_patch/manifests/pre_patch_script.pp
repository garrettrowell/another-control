class growell_patch::pre_patch_script (
  Enum['normal','high'] $priority = 'normal',
  Hash $pre_patch_commands,
  String $report_script_loc,
  Boolean $run_as_plan = false,
  Optional[Timestamp] $super_tuesday_end = undef,
){
  case $priority {
    'normal': {
      $_schedule = "${module_name} - Patch Window"
      $_exec_title_base = "${module_name} - Before patching - "
      $_notify_title_base = "${module_name} - Pre Patching Script"
    }
    'high': {
      $_schedule = "${module_name} - High Priority Patch Window"
      $_exec_title_base = "${module_name} - Before patching (High Priority) - "
      $_notify_title_base = "${module_name} - Pre Patching Script (High Priority)"
    }
  }

  if $run_as_plan {
    $_needs_ran = true
  } else {
    if $facts["${module_name}_report"].dig('pre_patching_script') {
      $cur = growell_patch::within_cur_month($facts["${module_name}_report"]['pre_patching_script']['timestamp'])
      if $cur {
        if $facts["${module_name}_report"]['pre_patching_script']['status'] == 'success' {
          if $super_tuesday_end > Timestamp($facts["${module_name}_report"]['pre_patching_script']['timestamp']) {
            $_needs_ran = true
          } else {
            $_needs_ran = false
          }
        } else {
          $_needs_ran = true
        }
      } else {
        $_needs_ran = true
      }
    } else {
      $_needs_ran = true
    }
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
      command  => "${report_script_loc} -d '${failure_data}'",
      schedule => $_schedule,
      tag      => ["${module_name}_pre_patching"],
    }

    # Run the post_patch_command(s)
    $pre_patch_commands.each |$cmd, $cmd_opts| {
      exec { "${_exec_title_base}${cmd}":
        *        => delete($cmd_opts, ['require', 'before', 'schedule', 'tag']),
        require  => Exec["${_notify_title_base} - failed"],
        before   => Class["${module_name}::${facts['kernel'].downcase}::patchday"],
        schedule => $_schedule,
        notify   => Exec["${_notify_title_base} - success"],
        tag      => ["${module_name}_pre_patching", "${module_name}_pre_script"],
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
      tag         => ["${module_name}_pre_patching"],
    }
  }

  # Make sure pre checks happen before any pre patch script
  Exec <| tag == "${module_name}_pre_check" |> -> Exec <| tag == "${module_name}_pre_script" |>
}
