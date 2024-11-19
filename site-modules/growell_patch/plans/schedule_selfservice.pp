plan growell_patch::schedule_selfservice(
  TargetSpec $targets,
  String[1] $day,
  Integer $week,
  Integer $offset,
  String[1] $hours,
  Optional[Enum['permanent','temporary']] $type = 'temporary',
  Optional[Integer] $max_runs = 1,
  Optional[String[1]] $reboot = 'ifneeded',
) {
  # collect facts
  run_plan('facts', 'targets' => $targets)

  # custom fact name
  $_override_fact = 'growell_patch_override'

  # manage fact file
  $results = apply($targets) {
    $fdir = "${facts['puppet_vardir']}/../../facter/facts.d"
    #    $_valid = $valid_for ? {
    #      'permanent' => 'permanent',
    #      'temporary' => Timestamp.new(),
    #    }
    $fpath = join([$fdir, "${_override_fact}.json"], '/')
    $cur_override = $facts[$_override_fact]
    $has_permanent = $cur_override.dig('permanent') != undef
    $has_temporary = $cur_override.dig('temporary') != undef
    file { $fpath:
      ensure  => present,
      content => to_json_pretty(
        {
          $_override_fact => {
            'temporary' => {
              'day'             => $day,
              'week'            => $week,
              'offset'          => $offset,
              'hours'           => $hours,
              'max_runs'        => $max_runs,
              'reboot'          => $reboot,
              'valid_for_month' => $_valid,
            },
            'has_perm'  => $has_permanent,
            'has_temp'  => $has_temporary
          }
        }
      ),
    }
  }

  $results.each |$result| {
    out::message($result.report)
  }
}
