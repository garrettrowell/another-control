plan growell_patch::patch_now(
  TargetSpec $targets,
) {
  # collect facts
  run_plan('facts', 'targets' => $targets)

  # patch now
  $results = apply($targets) {
    class { 'growell_patch':
      $patch_group => 'always',
    }
  }

  $results.each |$result| {
    out::message($result.report)
  }
}
