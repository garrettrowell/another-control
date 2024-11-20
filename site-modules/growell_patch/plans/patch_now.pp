plan growell_patch::patch_now(
  TargetSpec $targets,
) {
  # collect facts
  run_plan('facts', 'targets' => $targets)

  # patch now
  $results = apply($targets) {
    class { 'growell_patch':
      patch_group => 'always',
      run_as_plan => true,
    }
  }

  # run the agent after patching
  #  run_task('enterprise_tasks::run_puppet', $targets)

  # basic output
  $results.each |$result| {
    out::message($result.report)
  }
}
