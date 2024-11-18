plan growell_patch::schedule_selfservice(
  TargetSpec $targets,
) {
  # collect facts
  run_plan('facts', 'targets' => $targets)

  # manage fact file
  $results = apply($targets) {
    notify { "factpath: ${facts['factpath']}": }
    #    $fpath = join([split($facts['factpath'], ':')[0], 'growell_patch_override.json'], '/')
    #    file { $fpath:
    #      ensure  => present,
    #      content => {'thing1' => 'imatest'},
    #    }
  }

  $results.each |$result| {
    out::message($result.report)
  }
}
