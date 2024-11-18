plan growell_patch::schedule_selfservice(
  TargetSpec $targets,
  String[1] $day,
  Integer $week,
  Integer $offset,
  String[1] $hours,
  Optional[Enum['permanent','temporary']] $valid_for = 'temporary',
  Optional[Integer] $max_runs = 1,
  Optional[String[1]] $reboot = 'ifneeded',
) {
  $m_name = $module_name
  # collect facts
  run_plan('facts', 'targets' => $targets)

  # manage fact file
  $results = apply($targets) {
    $fdir = "${facts['puppet_vardir']}/../../facter/facts.d"
    $_valid = $valid_for ? {
      'permanent' => 'permanent',
      'temporary' => Timestamp.new(),
    }
    $fpath = join([$fdir, "${m_name}_override.json"], '/')
    file { $fpath:
      ensure  => present,
      content => to_json_pretty(
        {
          "${m_name}_override" => {
            'day'             => $day,
            'week'            => $week,
            'offset'          => $offset,
            'hours'           => $hours,
            'max_runs'        => $max_runs,
            'reboot'          => $reboot,
            'valid_for_month' => $_valid,
          }
        }
      ),
    }
  }

  $results.each |$result| {
    out::message($result.report)
  }
}
