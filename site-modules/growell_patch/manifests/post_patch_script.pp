class growell_patch::post_patch_script (
  Enum['normal','high'] $priority = 'normal',
  Hash $post_patch_commands,
){
  case $priority {
    'normal': {
      $_schedule = 'Growell_patch - Patch Window'
      $_exec_title_base = "Growell_patch - After patching - "
    }
    'high': {
      $_schedule = 'Growell_patch - High Priority Patch Window'
      $_exec_title_base = "Growell_patch - After patching (High Priority) - "
    }
  }

  $post_patch_commands.each |$cmd, $cmd_pots| {
    exec { "${_exec_title_base}${cmd}":
      *        => delete($cmd_opts, ['require', 'before', 'schedule', 'tag']),
      #      require  => Anchor['growell_patch::post'],
      schedule => $_schedule,
      tag      => ['growell_patch_post_patching', "${module_name}_post_script"],
    }
  }

  # Make sure post checks happen before any post patch script
  Exec <| tag == "${module_name}_post_check" |> -> Exec <| tag == "${module_name}_post_script" |>
}
