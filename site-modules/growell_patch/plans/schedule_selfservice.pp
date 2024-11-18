plan growell_patch::schedule_selfservice(
  TargetSpec $targets,
) {
  # collect facts
  run_plan('facts', 'targets' => $targets)

  # manage fact file
  $results = apply($targets) {
    $fdir = $facts['kernel'] ? {
      'Linux'   => '/opt/puppetlabs/puppet/cache/lib/facter',
      'windows' => 'C:/ProgramData/PuppetLabs/puppet/cache/lib/facter'
    }
    $fpath = join([$fdir, 'growell_patch_override.json'], '/')
    file { $fpath:
      ensure  => present,
      content => {'thing1' => 'imatest'},
    }
  }

  $results.each |$result| {
    out::message($result.report)
  }
}
