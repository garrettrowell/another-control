plan growell_patch::schedule_selfservice(
  TargetSpec $targets,
) {
  # collect facts
  run_plan('facts', 'targets' => $targets)

  # manage fact file
  $results = apply($targets) {
    $fdir = $facts['kernel'] ? {
      'Linux'   => '/opt/puppetlabs/facter/facts.d',
      'windows' => 'C:/ProgramData/PuppetLabs/facter/facts.d'
    }
    $fpath = join([$fdir, 'growell_patch_override.json'], '/')
    file { $fpath:
      ensure  => present,
      content => "{'thing1' => 'imatest'}",
    }
  }

  $results.each |$result| {
    out::message($result.report)
  }
}
