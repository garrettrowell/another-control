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
    # patching_as_code uses deferred functions to write these file contents,
    # which does not play nicely within apply blocks
    #    File <| title == 'Patching as Code - Save Patch Run Info' |> {
    #      content => undef,
    #    }
    #    File <| title == 'Patching as Code - Save High Priority Patch Run Info' |> {
    #      contentn => undef,
    #    }
  }

  # run the agent after patching
  run_task('enterprise_tasks::run_puppet', $targets)

  # basic output
  $results.each |$result| {
    out::message($result.report)
  }
}
