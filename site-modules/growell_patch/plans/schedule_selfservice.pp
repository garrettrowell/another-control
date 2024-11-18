plan growell_patch::schedule_selfservice.pp(
  TargetSpec $targets,
) {
  # install agent if needed, collect facts
  apply_prep($targets)

  # manage fact file
  apply($targets) {
    $fpath = join([split($facts['factpath'], ':')[0], 'growell_patch_override.json'], '/')
    file { $fpath:
      ensure  => present,
      content => {'thing1' => 'imatest'},
    }
  }
}
