class growell_patch::post_check (
  Enum['normal', 'high'] $priority = 'normal',
  Hash $exec_args,
){
  case $priority {
    'normal': {
      $_exec_title = 'post_check_script'
      $_exec_schedule = 'Growell_patch - Patch Window'
    }
    'high': {
      $_exec_title = 'post_check_script (High Priority)'
      $_exec_schedule = 'Growell_patch - High Priority Patch Window'
    }
  }

  exec { $_exec_title:
    schedule => $_exec_schedule,
    *        => $exec_args
  }
}
