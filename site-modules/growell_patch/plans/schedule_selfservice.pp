plan growell_patch::schedule_selfservice(
  TargetSpec $targets,
  Optional[String[1]] $day = undef,
  Optional[Integer] $week = undef,
  Optional[Integer] $offset = undef,
  Optional[String[1]] $hours = undef,
  Optional[Enum['permanent','temporary','exclusion']] $type = 'temporary',
  Optional[Integer] $max_runs = 1,
  Optional[String[1]] $reboot = 'ifneeded',
  Optional[Enum['add', 'remove']] $action = 'add',
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
    #    $has_permanent = 'permanent' in $cur_override
    #    $has_temporary = 'temporary' in $cur_override

    case $type {
      'temporary': {
        if $action == 'add' {
          $fact_content = {
            $_override_fact => deep_merge(
              $cur_override, {
                'temporary' => {
                  'day'       => $day,
                  'week'      => $week,
                  'offset'    => $offset,
                  'hours'     => $hours,
                  'max_runs'  => $max_runs,
                  'reboot'    => $reboot,
                  'timestamp' => Timestamp.new(),
                }
              }
            )
          }
        } else {
          $fact_content = {
            $_override_fact => $cur_override.filter |$k,$v| { $k != 'temporary' }
          }
        }
        #if $has_permanent {
        #  $fact_content = {
        #    $_override_fact => {
        #      'temporary' => {
        #        'day'       => $day,
        #        'week'      => $week,
        #        'offset'    => $offset,
        #        'hours'     => $hours,
        #        'max_runs'  => $max_runs,
        #        'reboot'    => $reboot,
        #        'timestamp' => Timestamp.new()
        #      },
        #      'permanent' => $cur_override['permanent'],
        #    }
        #  }
        #} else {
        #  $fact_content = {
        #    $_override_fact => {
        #      'temporary' => {
        #        'day'       => $day,
        #        'week'      => $week,
        #        'offset'    => $offset,
        #        'hours'     => $hours,
        #        'max_runs'  => $max_runs,
        #        'reboot'    => $reboot,
        #        'timestamp' => Timestamp.new()
        #      },
        #    }
        #  }
        #}
      }
      'permanent': {
        if $action == 'add' {
          $fact_content = {
            $_override_fact => deep_merge(
              $cur_override, {
                'permanent' => {
                  'day'      => $day,
                  'week'     => $week,
                  'offset'   => $offset,
                  'hours'    => $hours,
                  'max_runs' => $max_runs,
                  'reboot'   => $reboot,
                }
              }
            )
          }
        } else {
          $fact_content = {
            $_override_fact => $cur_override.filter |$k,$v| { $k != 'permanent' }
          }
        }
        #if $has_temporary {
        #  $fact_content = {
        #    $_override_fact => {
        #      'temporary' => $cur_override['temporary'],
        #      'permanent' => {
        #        'day'       => $day,
        #        'week'      => $week,
        #        'offset'    => $offset,
        #        'hours'     => $hours,
        #        'max_runs'  => $max_runs,
        #        'reboot'    => $reboot,
        #      }
        #    }
        #  }
        #} else {
        #  $fact_content = {
        #    $_override_fact => {
        #      'permanent' => {
        #        'day'       => $day,
        #        'week'      => $week,
        #        'offset'    => $offset,
        #        'hours'     => $hours,
        #        'max_runs'  => $max_runs,
        #        'reboot'    => $reboot,
        #      }
        #    }
        #  }
        #}
      }
      'exclusion': {
        if $action == 'add' {
          $fact_content = {
            $_override_fact => deep_merge($cur_override, {'exclusion' => true})
          }
        } else {
          $fact_content = {
            $_override_fact => $cur_override.filter |$k,$v| { $k != 'exclusion' }
          }
        }
      }
    }

    file { $fpath:
      ensure  => present,
      content => to_json_pretty($fact_content),
    }
  }

  $results.each |$result| {
    out::message($result.report)
  }
}
