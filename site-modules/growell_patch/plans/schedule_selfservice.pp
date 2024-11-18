plan growell_patch::schedule_selfservice(
  TargetSpec $targets,
  String[1] $day,
  String[1] $week,
  String[1] $offset,
  String[1] $hours,
  Optional[String[1]] $max_runs = 1,
  Optional[String[1]] $reboot = 'ifneeded',
) {
  # collect facts
  run_plan('facts', 'targets' => $targets)

  # manage fact file
  $results = apply($targets) {
    $fdir = "${facts['puppet_vardir']}/../../facter/facts.d"
    #    $fdir = $facts['kernel'] ? {
    #      'Linux'   => ${facts['puppet_vardir']}/../../facter/facts.d",
    #      'windows' => 'C:/ProgramData/PuppetLabs/facter/facts.d'
    #    }
    $fpath = join([$fdir, 'growell_patch_override.json'], '/')
    file { $fpath:
      ensure  => present,
      content => to_json_pretty(
        {
          'growell_patch_override' => {
            'day'      => $day,
            'week'     => $week,
            'offset'   => $offset,
            'hours'    => $hours,
            'max_runs' => $max_runs,
            'reboot'   => $reboot,
          }
        }
      ),
    }
  }

  $results.each |$result| {
    out::message($result.report)
  }
}
