class growell_patch::post_check (
  Enum['normal', 'high'] $priority = 'normal',
  Hash $exec_args,
  String $report_script_loc,
){
  case $priority {
    'normal': {
      $_exec_title = 'post_check_script'
      $_schedule = 'Growell_patch - Patch Window'
      $_notify_title_base = 'Growell_patch - Post Check'
    }
    'high': {
      $_exec_title = 'post_check_script (High Priority)'
      $_schedule = 'Growell_patch - High Priority Patch Window'
      $_notify_title_base = 'Growell_patch - Post Check (High Priority)'
    }
  }

  if $facts['growell_patch_report'].dig('post_check') {
    $cur = growell_patch::within_cur_month($facts['growell_patch_report']['post_check']['timestamp'])
    if $cur {
      $_needs_ran = Timestamp.new() < Timestamp($facts['growell_patch_report']['post_check']['timestamp'])
    } else {
      $_needs_ran = true
    }
  } else {
    $_needs_ran = true
  }

  if $_needs_ran {
    # Initially record that the post check failed
    $failure_data = stdlib::to_json(
      {
        'post_check' => {
          'status' => 'failed',
          'timestamp' => Timestamp.new()
        }
      }
    )
    exec { "${_notify_title_base} - failed":
      command     => "${report_script_loc} -d '${failure_data}'",
      before      => Exec[$_exec_title],
      schedule    => $_schedule,
    }

    # Run the post check
    exec { $_exec_title:
      schedule => $_schedule,
      *        => $exec_args
    }

    # In the event the post check fails, this resource will get skipped
    $success_data = stdlib::to_json(
      {
        'post_check' => {
          'status' => 'success',
          'timestamp' => Timestamp.new()
        }
      }
    )
    exec { "${_notify_title_base} - success":
      command     => "${report_script_loc} -d '${success_data}'",
      refreshonly => true,
      subscribe   => Exec[$_exec_title],
      schedule    => $_schedule,
    }
  }
}
