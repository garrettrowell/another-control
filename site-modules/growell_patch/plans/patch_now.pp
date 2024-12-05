plan growell_patch::patch_now(
  TargetSpec $targets,
  Optional[Enum['always', 'never', 'ifneeded']] $pre_reboot = 'always',
  Optional[Enum['always', 'never', 'ifneeded']] $post_reboot = 'always',
) {
  # collect facts
  run_plan('facts', 'targets' => $targets, '_catch_errors' => true)

  out::message($targets)

  # patch now
  $results = apply($targets, '_description' => 'Main Patching Run', '_catch_errors' => true) {
    class { 'growell_patch':
      patch_group => 'always',
      run_as_plan => true,
    }
  }

  # basic output
  $results.each |$result| {
    out::message($result.report)
  }
}
