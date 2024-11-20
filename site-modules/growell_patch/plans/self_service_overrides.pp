plan growell_patch::self_service_overrides(
  TargetSpec $targets,
  Optional[String[1]] $day = undef,
  Optional[Integer] $week = undef,
  Optional[Integer] $offset = undef,
  Optional[String[1]] $hours = undef,
  Optional[Enum['permanent','temporary','exclusion','blocklist']] $type = 'temporary',
  Optional[Enum['strict','fuzzy']] $blocklist_mode = 'strict',
  Optional[Array] $blocklist = [],
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
    $fpath = join([$fdir, "${_override_fact}.json"], '/')
    $cur_override = $facts[$_override_fact]

    case $type {
      'blocklist': {
        if $action == 'add' {
          $fact_content = {
            $_override_fact => deep_merge(
              $cur_override, {
                'blocklist' => {
                  'mode' => $blocklist_mode,
                  'list' => $blocklist,
                }
              }
            )
          }
        } else {
          $fact_content = {
            $_override_fact => $cur_override.filter |$k,$v| { $k != 'blocklist' }
          }
        }
      }
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
