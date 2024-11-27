plan growell_patch::self_service_overrides(
  TargetSpec $targets,
  Enum['permanent','temporary','exclusion','blocklist'] $type,
  Enum['add', 'remove'] $action,
  Optional[String[1]] $day = undef,
  Optional[Integer] $week = undef,
  Optional[Integer] $offset = undef,
  Optional[String[1]] $hours = undef,
  Optional[Enum['strict','fuzzy']] $blocklist_mode = 'fuzzy',
  Optional[Array] $blocklist = [],
  Optional[Integer] $max_runs = 3,
  Optional[Enum['always', 'never', 'ifneeded']] $post_reboot = 'ifneeded',
  Optional[Enum['always', 'never', 'ifneeded']] $pre_reboot  = 'ifneeded',
) {
  # Validate the required Parameters are passed for the given override 'type'
  if $action == 'add' {
    case $type {
      'blocklist': {
        unless ($blocklist != [] and $blocklist_mode != undef) {
          fail_plan('$blocklist and $blocklist_mode are required parameters when $type = blocklist and $action = add')
        }
      }
      'permanent': {
        unless ($day != undef and $week != undef and $offset != undef and $hours != undef) {
          fail_plan('$day, $week, $offset and $hours are required parameters when $type = permanent and $action = add')
        }
      }
      'temporary': {
        unless ($day != undef and $week != undef and $offset != undef and $hours != undef) {
          fail_plan('$day, $week, $offset and $hours are required parameters when $type = temporary and $action = add')
        }
      }
    }
  }
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
          # When removing a blocklist first check if we have an override_fact first
          if $cur_override {
            $fact_content = {
              $_override_fact => $cur_override.filter |$k,$v| { $k != 'blocklist' }
            }
          }
        }
      }
      'temporary': {
        if $action == 'add' {
          $fact_content = {
            $_override_fact => deep_merge(
              $cur_override, {
                'temporary' => {
                  'day'         => $day,
                  'week'        => $week,
                  'offset'      => $offset,
                  'hours'       => $hours,
                  'max_runs'    => $max_runs,
                  'post_reboot' => $post_reboot,
                  'pre_reboot'  => $pre_reboot,
                  'timestamp'   => Timestamp.new(),
                }
              }
            )
          }
        } else {
          # When removing a temporary override, first check if we have an override_fact
          if $cur_override {
            $fact_content = {
              $_override_fact => $cur_override.filter |$k,$v| { $k != 'temporary' }
            }
          }
        }
      }
      'permanent': {
        if $action == 'add' {
          $fact_content = {
            $_override_fact => deep_merge(
              $cur_override, {
                'permanent' => {
                  'day'         => $day,
                  'week'        => $week,
                  'offset'      => $offset,
                  'hours'       => $hours,
                  'max_runs'    => $max_runs,
                  'post_reboot' => $post_reboot,
                  'pre_reboot'  => $pre_reboot,
                }
              }
            )
          }
        } else {
          # When removing a permanent override, first check if we have an override_fact
          if $cur_override {
            $fact_content = {
              $_override_fact => $cur_override.filter |$k,$v| { $k != 'permanent' }
            }
          }
        }
      }
      'exclusion': {
        if $action == 'add' {
          $fact_content = {
            $_override_fact => deep_merge($cur_override, {'exclusion' => true})
          }
        } else {
          # When removing an exclusion, first check if we have an override_fact
          if $cur_override {
            $fact_content = {
              $_override_fact => $cur_override.filter |$k,$v| { $k != 'exclusion' }
            }
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
