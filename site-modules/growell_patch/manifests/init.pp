# @summary This module began life as the 'puppetlabs/patching_as_code' module (v2.0.0)
#   It has since been heavily modified in order to support self-service workflows
#
# A description of what this class does
#
# @param patch_schedule
# @param patch_group
# @param pre_patch_script
# @param post_patch_script
# @param pre_reboot_script
# @param install_options
# @param blocklist
# @param blocklist_mode
# @param high_priority_patch_group
# @param enable_patching
# @param high_priority_only
# @param security_only
# @param allowlist
# @param high_priority_list
# @param windows_prefetch_before
# @param wsus_url
# @param pin_blocklist
#
# @example
#   include growell_patch
class growell_patch (
  Hash[String[1], Growell_patch::Patch_schedule] $patch_schedule,
  Variant[String[1], Array[String[1]]]           $patch_group,
  Boolean                                        $enable_patching           = true,
  Boolean                                        $high_priority_only        = false,
  Boolean                                        $security_only             = false,
  Boolean                                        $pin_blocklist             = false,
  Boolean                                        $run_as_plan               = false,
  Boolean                                        $classify_pe_patch         = true,
  Boolean                                        $fact_upload               = true,
  Boolean                                        $patch_on_metered_links    = false,
  Enum['strict', 'fuzzy']                        $blocklist_mode            = 'fuzzy',
  Optional[Array]                                $install_options           = undef,
  Array                                          $allowlist                 = [],
  Array                                          $blocklist                 = [],
  Array                                          $high_priority_list        = [],
  Array                                          $unsafe_process_list       = [],
  Optional[String[1]]                            $pre_check_script          = undef,
  Optional[String[1]]                            $post_check_script         = undef,
  Optional[String[1]]                            $pre_reboot_script         = undef,
  String[1]                                      $high_priority_patch_group,
  Optional[String[1]]                            $windows_prefetch_before   = undef,
  Optional[Stdlib::HTTPUrl]                      $wsus_url                  = undef,
) {
  # Create extra stages so we can reboot before and after
  stage { "${module_name}_post_reboot": }
  stage { "${module_name}_after_post_reboot": }
  #  stage { "${module_name}_pre_reboot": }
  # Stage["${module_name}_pre_reboot"] -> Stage['main'] -> Stage["${module_name}_post_reboot"]
  Stage['main'] -> Stage["${module_name}_post_reboot"] -> Stage["${module_name}_after_post_reboot"]


  # Ensure we work with a $patch_groups array for further processing
  $patch_groups = Array($patch_group, true)

  #  # Verify if all of $patch_groups point to a valid patch schedule
  #  $patch_groups.each |$pg| {
  #    unless $patch_schedule[$pg] or $pg in ['always', 'never'] {
  #      fail("Patch group ${pg} is not valid as no associated schedule was found!\nEnsure the ${module_name}::patch_schedule parameter contains a schedule for this patch group.") #lint:ignore:140chars
  #    }
  #  }
  #
  #  # Verify if the $high_priority_patch_group points to a valid patch schedule
  #  unless $patch_schedule[$high_priority_patch_group] or $high_priority_patch_group in ['always', 'never'] {
  #    fail("High Priority Patch group ${high_priority_patch_group} is not valid as no associated schedule was found!\nEnsure the ${module_name}::patch_schedule parameter contains a schedule for this patch group.") #lint:ignore:140chars
  #  }

  # Verify the puppet_confdir from the puppetlabs/puppet_agent module is present
  unless $facts['puppet_confdir'] {
    fail("The ${module_name} module depends on the puppetlabs/puppet_agent module, please add it to your setup!")
  }

  # Write local config file for unsafe processes
  file { "${facts['puppet_confdir']}/patching_unsafe_processes":
    ensure    => file,
    content   => $unsafe_process_list.join("\n"),
    show_diff => false,
  }

  if $classify_pe_patch {
    class { 'pe_patch':
      patch_group => join($patch_groups, ' '),
      fact_upload => $fact_upload,
    }
  }

  # Ensure yum-utils package is installed on RedHat/CentOS for needs-restarting utility
  if $facts['os']['family'] == 'RedHat' {
    ensure_packages('yum-utils')
  }

  $_pe_patch_cachedir = $facts['kernel'] ? {
    'windows' => 'C:/ProgramData/PuppetLabs/pe_patch',
    'Linux'   => '/opt/puppetlabs/pe_patch',
  }

  # Check for any self-service overrides +
  # Convert our custom schedule into the form used by patching_as_code.
  #
  # Using the growell_patch::calc_patchday function we are able to determine the 'day_of_week'
  #   and 'count_of_week' based off of our 'day', 'week', and 'offset' params.
  #
  # The growell_patch::self_service_overrides Plan can be used to create patching overrides for desired nodes
  #
  $_override_fact = 'growell_patch_override'
  if $facts[$_override_fact] {
    # Self-service fact detected
    $_has_perm_override           = 'permanent' in $facts[$_override_fact] # indicates a permanent schedule change
    $_has_temp_override           = 'temporary' in $facts[$_override_fact] # indicates a schedule change valid for 1 month
    $_has_exclusion_override      = 'exclusion' in $facts[$_override_fact] # indicates patches should not be applied unless initiated by the patch_now plan
    $_has_temp_exclusion_override = 'temporary_exclusion' in $facts[$_override_fact] # same as $_has_exclusion_override but only valid for 1 month

    if ($run_as_plan and 'always' in $patch_group) {
      # When running the growell_patch::patch_now plan, we need to set the group to 'always'
      $_patch_group    = 'always'
      $_patch_schedule = {}
      # Override the configuration file so that it won't actually get updated.
      # This eliminates the need to run the agent a second time in the plan
      File <| title == "${module_name}_configuration.json" |> {
        noop => true,
      }
      # pe_patch's 'patch_group' file also should not get updated
      File <| title == "${_pe_patch_cachedir}/patch_group" |> {
        noop => true,
      }
    } else {
      # Not patching using growell_patch::patch_now plan.
      # Need to determine which override is applicable if any
      if $_has_exclusion_override {
        # We have an exclusion so node is 'Patch by Owner'
        $_patch_group    = 'never'
        $_patch_schedule = {}
      } else {
        # No exclusion so next check for temp_exclusion
        if $_has_temp_exclusion_override {
          # Check if the temp_exclusion is applicable to the current month
          $_within_cur_month = growell_patch::within_cur_month($facts[$_override_fact]['temporary_exclusion']['timestamp'])
          if $_within_cur_month {
            # Since the temp_exclusion is for the current month honor it
            $_patch_group    = 'never'
            $_patch_schedule = {}
          } else {
            # Since the temp_exclusion is not applicable, next check for temp_override
            if $_has_temp_override {
              # Check if the temp_override is applicable to the current month
              $_within_cur_month = growell_patch::within_cur_month($facts[$_override_fact]['temporary']['timestamp'])
              if $_within_cur_month {
                # Since the temp_override is for the current month honor it
                $_patch_group = 'temporary_override'
                $_patch_day   = growell_patch::calc_patchday(
                  $facts[$_override_fact]['temporary']['day'],
                  $facts[$_override_fact]['temporary']['week'],
                  $facts[$_override_fact]['temporary']['offset'],
                )
                $_patch_schedule = {
                  $_patch_group => {
                    'day_of_week'   => $_patch_day['day_of_week'],
                    'count_of_week' => $_patch_day['count_of_week'],
                    'hours'         => $facts[$_override_fact]['temporary']['hours'],
                    'max_runs'      => String($facts[$_override_fact]['temporary']['max_runs']),
                    'post_reboot'   => $facts[$_override_fact]['temporary']['post_reboot'],
                    'pre_reboot'    => $facts[$_override_fact]['temporary']['pre_reboot'],
                  }
                }
              } else {
                # Since the temp_override is not applicable, next check for perm_override
                if $_has_perm_override {
                  # Since there is a perm_override, honor it
                  $_patch_group = 'permanent_override'
                  $_patch_day   = growell_patch::calc_patchday(
                    $facts[$_override_fact]['permanent']['day'],
                    $facts[$_override_fact]['permanent']['week'],
                    $facts[$_override_fact]['permanent']['offset'],
                  )
                  $_patch_schedule = {
                    $_patch_group => {
                      'day_of_week'   => $_patch_day['day_of_week'],
                      'count_of_week' => $_patch_day['count_of_week'],
                      'hours'         => $facts[$_override_fact]['permanent']['hours'],
                      'max_runs'      => String($facts[$_override_fact]['permanent']['max_runs']),
                      'post_reboot'   => $facts[$_override_fact]['permanent']['post_reboot'],
                      'pre_reboot'    => $facts[$_override_fact]['permanent']['pre_reboot'],
                    }
                  }
                } else {
                  # Since there is no perm_override, fall back to configured schedule
                  $_patch_group = $patch_group
                  $_patch_schedule = $patch_schedule.reduce({}) |$memo, $x| {
                    $memo + {
                      $x[0] => {
                        'day_of_week'   => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['day_of_week'],
                        'count_of_week' => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['count_of_week'],
                        'hours'         => $x[1]['hours'],
                        'max_runs'      => $x[1]['max_runs'],
                        'post_reboot'   => $x[1]['post_reboot'],
                        'pre_reboot'    => $x[1]['pre_reboot'],
                      }
                    }
                  }
                } # end of if $_has_perm_override {...} else {...}
              } # end of if $_within_cur_month {...} else {...}
            } else {
              # Since there is no temp_override, next check for perm_override
              if $_has_perm_override {
                # Since there is a perm_override, honor it
                $_patch_group = 'permanent_override'
                $_patch_day   = growell_patch::calc_patchday(
                  $facts[$_override_fact]['permanent']['day'],
                  $facts[$_override_fact]['permanent']['week'],
                  $facts[$_override_fact]['permanent']['offset'],
                )
                $_patch_schedule = {
                  $_patch_group => {
                    'day_of_week'   => $_patch_day['day_of_week'],
                    'count_of_week' => $_patch_day['count_of_week'],
                    'hours'         => $facts[$_override_fact]['permanent']['hours'],
                    'max_runs'      => String($facts[$_override_fact]['permanent']['max_runs']),
                    'post_reboot'   => $facts[$_override_fact]['permanent']['post_reboot'],
                    'pre_reboot'    => $facts[$_override_fact]['permanent']['pre_reboot'],
                  }
                }
              } else {
                # Since there is no perm_override, fall back to configured schedule
                $_patch_group = $patch_group
                $_patch_schedule = $patch_schedule.reduce({}) |$memo, $x| {
                  $memo + {
                    $x[0] => {
                      'day_of_week'   => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['day_of_week'],
                      'count_of_week' => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['count_of_week'],
                      'hours'         => $x[1]['hours'],
                      'max_runs'      => $x[1]['max_runs'],
                      'post_reboot'   => $x[1]['post_reboot'],
                      'pre_reboot'    => $x[1]['pre_reboot'],
                    }
                  }
                }
              } # end of if $_has_perm_override {...} else {...}
            } # end of if $_has_temp_override {...} else {...}
          } # end of if $_within_cur_month {...} else {...}
        } else {
          # Since there's no temp_exclusion, next check for temp_override
          if $_has_temp_override {
            # Check if the temp_override is applicable to the current month
            $_within_cur_month = growell_patch::within_cur_month($facts[$_override_fact]['temporary']['timestamp'])
            if $_within_cur_month {
              # Since the temp_override is for the current month honor it
              $_patch_group = 'temporary_override'
              $_patch_day   = growell_patch::calc_patchday(
                $facts[$_override_fact]['temporary']['day'],
                $facts[$_override_fact]['temporary']['week'],
                $facts[$_override_fact]['temporary']['offset'],
              )
              $_patch_schedule = {
                $_patch_group => {
                  'day_of_week'   => $_patch_day['day_of_week'],
                  'count_of_week' => $_patch_day['count_of_week'],
                  'hours'         => $facts[$_override_fact]['temporary']['hours'],
                  'max_runs'      => String($facts[$_override_fact]['temporary']['max_runs']),
                  'post_reboot'   => $facts[$_override_fact]['temporary']['post_reboot'],
                  'pre_reboot'    => $facts[$_override_fact]['temporary']['pre_reboot'],
                }
              }
            } else {
              # Since the temp_override is not applicable, next check for perm_override
              if $_has_perm_override {
                # Since there is a perm_override, honor it
                $_patch_group = 'permanent_override'
                $_patch_day   = growell_patch::calc_patchday(
                  $facts[$_override_fact]['permanent']['day'],
                  $facts[$_override_fact]['permanent']['week'],
                  $facts[$_override_fact]['permanent']['offset'],
                )
                $_patch_schedule = {
                  $_patch_group => {
                    'day_of_week'   => $_patch_day['day_of_week'],
                    'count_of_week' => $_patch_day['count_of_week'],
                    'hours'         => $facts[$_override_fact]['permanent']['hours'],
                    'max_runs'      => String($facts[$_override_fact]['permanent']['max_runs']),
                    'post_reboot'   => $facts[$_override_fact]['permanent']['post_reboot'],
                    'pre_reboot'    => $facts[$_override_fact]['permanent']['pre_reboot'],
                  }
                }
              } else {
                # Since there is no perm_override, fall back to configured schedule
                $_patch_group = $patch_group
                $_patch_schedule = $patch_schedule.reduce({}) |$memo, $x| {
                  $memo + {
                    $x[0] => {
                      'day_of_week'   => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['day_of_week'],
                      'count_of_week' => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['count_of_week'],
                      'hours'         => $x[1]['hours'],
                      'max_runs'      => $x[1]['max_runs'],
                      'post_reboot'   => $x[1]['post_reboot'],
                      'pre_reboot'    => $x[1]['pre_reboot'],
                    }
                  }
                }
              } # end if $_has_perm_override {...} else {...}
            } # end if $_within_cur_month {...} else {...}
          } else {
            # Since there's no temp_override, next check for perm_override
            if $_has_perm_override {
              # Since there is a perm_override, honor it
              $_patch_group = 'permanent_override'
              $_patch_day   = growell_patch::calc_patchday(
                $facts[$_override_fact]['permanent']['day'],
                $facts[$_override_fact]['permanent']['week'],
                $facts[$_override_fact]['permanent']['offset'],
              )
              $_patch_schedule = {
                $_patch_group => {
                  'day_of_week'   => $_patch_day['day_of_week'],
                  'count_of_week' => $_patch_day['count_of_week'],
                  'hours'         => $facts[$_override_fact]['permanent']['hours'],
                  'max_runs'      => String($facts[$_override_fact]['permanent']['max_runs']),
                  'post_reboot'   => $facts[$_override_fact]['permanent']['post_reboot'],
                  'pre_reboot'    => $facts[$_override_fact]['permanent']['pre_reboot'],
                }
              }
            } else {
              # Since there is no perm_override, fall back to configured schedule
              $_patch_group = $patch_group
              $_patch_schedule = $patch_schedule.reduce({}) |$memo, $x| {
                $memo + {
                  $x[0] => {
                    'day_of_week'   => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['day_of_week'],
                    'count_of_week' => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['count_of_week'],
                    'hours'         => $x[1]['hours'],
                    'max_runs'      => $x[1]['max_runs'],
                    'post_reboot'   => $x[1]['post_reboot'],
                    'pre_reboot'    => $x[1]['pre_reboot'],
                  }
                }
              }
            } # end of if $_has_perm_override {...} else {...}
          } # end of if $_has_temp_override {...} else {...}
        } # end of if $_has_temp_exclusion_override {...} else {...}
      } # end of if $_has_exclusion_override {...} else {...}
    } # end of if ($run_as_plan and 'always' in $patch_group) {...} else {...}
  } else {
    # No self-service fact detected
    if ($run_as_plan and 'always' in $patch_group) {
      # When running the growell_patch::patch_now plan, we need to set the group to 'always'
      $_patch_group    = 'always'
      $_patch_schedule = {}
      # Override the configuration file so that it won't actually get updated.
      # This eliminates the need to run the agent a second time in the plan
      File <| title == "${module_name}_configuration.json" |> {
        noop => true,
      }
      # pe_patch's 'patch_group' file also should not get updated
      File <| title == "${_pe_patch_cachedir}/patch_group" |> {
        noop => true,
      }
    } else {
      # Not patching using growell_patch::patch_now plan.
      # Calculate the patchday
      $_patch_group = $patch_group
      $_patch_schedule = $patch_schedule.reduce({}) |$memo, $x| {
        $memo + {
          $x[0] => {
            'day_of_week'   => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['day_of_week'],
            'count_of_week' => growell_patch::calc_patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['count_of_week'],
            'hours'         => $x[1]['hours'],
            'max_runs'      => $x[1]['max_runs'],
            'post_reboot'   => $x[1]['post_reboot'],
            'pre_reboot'    => $x[1]['pre_reboot'],
          }
        }
      }
    } # end of if ($run_as_plan and 'always' in $patch_group) {...} else {...}
  } # end of if $facts[$_override_fact {...} else {...}

  # Process the configured groups so we can determine the proper outcome
  $result = growell_patch::process_groups($_patch_group, $_patch_schedule, $high_priority_patch_group, $windows_prefetch_before)
  # Determine if we will be patching
  $_is_patchday               = $result['normal_patch']['is_patch_day']
  $_is_high_prio_patch_day    = $result['high_prio_patch']['is_patch_day']
  # Determine if we are in the patch window
  $_in_patch_window           = $result['normal_patch']['window']['within']
  $_in_high_prio_patch_window = $result['high_prio_patch']['window']['within']
  # Determine if we need to prefetch the windows kb's
  $_in_prefetch_window           = $result['normal_patch']['prefetch_window']['within']
  $_in_high_prio_prefetch_window = $result['high_prio_patch']['prefetch_window']['within']
  # Determine if we are before/after the various windows
  $_before_patch_window              = $result['normal_patch']['window']['before']
  $_after_patch_window               = $result['normal_patch']['window']['after']
  $_before_prefetch_window           = $result['normal_patch']['prefetch_window']['before']
  $_after_prefetch_window            = $result['normal_patch']['prefetch_window']['after']
  $_before_high_prio_patch_window    = $result['high_prio_patch']['window']['before']
  $_after_high_prio_patch_window     = $result['high_prio_patch']['window']['after']
  $_before_high_prio_prefetch_window = $result['high_prio_patch']['prefetch_window']['before']
  $_after_high_prio_prefetch_window  = $result['high_prio_patch']['prefetch_window']['after']
  # Determine the longest window (in seconds) that applies
  $_longest_duration = $result['longest_duration']
  # Determine the current active pg
  $_active_pg = $result['normal_patch']['active_pg']
  # Determine reboot
  $_post_reboot           = $result['normal_patch']['post_reboot']
  $_pre_reboot            = $result['normal_patch']['pre_reboot']
  $_high_prio_post_reboot = $result['high_prio_patch']['post_reboot']
  $_high_prio_pre_reboot  = $result['high_prio_patch']['pre_reboot']
  # Avoid having to call $facts['kernel'].downcase a ton of times
  $_kern = $facts['kernel'].downcase
  # Calculate when this months supertuesday is for comparisons later
  $_super_tuesday       = growell_patch::calc_supertuesday()
  $_super_tuesday_start = Timestamp("${_super_tuesday['start_time']}")
  $_super_tuesday_end   = Timestamp("${_super_tuesday['end_time']}")

  # Create a reporting script that we can call via Exec resources to keep track of whats happened during the patching process
  case $_kern {
    'linux': {
      $report_script_loc = "/opt/puppetlabs/${module_name}/reporting.rb"
      $report_script_file = $report_script_loc
    }
    'windows': {
      $report_script_file = "C:/ProgramData/PuppetLabs/${module_name}/reporting.rb"
      $report_script_loc = "\"C:/Program Files/Puppet Labs/Puppet/puppet/bin/ruby.exe\" ${report_script_file}"
    }
  }
  file { "${facts['puppet_vardir']}/../../${module_name}":
    ensure => directory,
    before => File[$report_script_file],
  }

  file { $report_script_file:
    ensure  => present,
    mode    => '0700',
    content => epp("${module_name}/reporting.rb.epp"),
  }

  # Configure the agents runtimeout accordingly
  $runtimeout_cfg_section = 'agent'
  if ($_is_patchday or $_is_high_prio_patch_day) {
    # Here it is patchday
    if ($_before_patch_window or $_before_prefetch_window or $_before_high_prio_patch_window or $_before_high_prio_prefetch_window) {
      # Before any patching or prefetching, set the runtimeout to the longest duration
      if defined(Class['puppet_agent']) {
        $filt_cfg = $puppet_agent::config.filter |$cfg| { $cfg['setting'] == 'runtimeout' }
        if $filt_cfg.size > 0 {
          # Here the puppet_agent class is defined and the runtimeout is being managed
          $filt_cfg.each |$hsh| {
            Ini_setting <| title == "puppet-${hsh['section']}-${hsh['setting']}" |> {
              ensure => present,
              value  => $_longest_duration,
            }
          }
        } else {
          # Here the puppet_agent class is defined and the runtimeout is not being managed
          ini_setting { "puppet-${runtimeout_cfg_section}-runtimeout":
            ensure  => present,
            section => $runtimeout_cfg_section,
            setting => 'runtimeout',
            value   => $_longest_duration,
            path    => $puppet_agent::params::config,
          }
        }
      } else {
        # Here the puppet agent_class is not defined elsewhere
        class { 'puppet_agent':
          config => [
            { section => $runtimeout_cfg_section, setting => 'runtimeout', value => $_longest_duration },
          ],
        }
      }
    } elsif ($_after_patch_window or $_after_high_prio_patch_window) {
      # After patching the runtimeout should either be set to what it was previously set to, or back to the default
      if defined(Class['puppet_agent']) {
        $filt_cfg = $puppet_agent::config.filter |$cfg| { $cfg['setting'] == 'runtimeout' }
        if $filt_cfg.size > 0 {
          # Here the puppet_agent class is defined and the runtimeout is being managed
          $filt_cfg.each |$hsh| {
            Ini_setting <| title == "puppet-${hsh['section']}-${hsh['setting']}" |> {
              ensure => present,
              value  => $hsh['value'],
            }
          }
        } else {
          # Here the puppet_agent class is defined but the runtimeout is not being managed
          ini_setting { "puppet-${runtimeout_cfg_section}-runtimeout":
            ensure  => absent,
            section => $runtimeout_cfg_section,
            setting => 'runtimeout',
            path    => $puppet_agent::params::config,
          }
        }
      } else {
        # Here  the puppet_agent class is not defined
        class { 'puppet_agent':
          config => [
            { section => $runtimeout_cfg_section, setting => 'runtimeout', ensure => absent },
          ],
        }
      }
    }
  }

  # Determine the available updates if any
  if $facts['pe_patch'] {
    $available_updates = $_kern ? {
      'windows' => if $security_only and !$high_priority_only {
        unless $facts['pe_patch']['missing_security_kbs'].empty {
          $facts['pe_patch']['missing_security_kbs']
        } else {
          $facts['pe_patch']['missing_update_kbs']
        }
      } elsif !$high_priority_only {
        $facts['pe_patch']['missing_update_kbs']
      } else {
        []
      },
      'linux' => if $security_only and !$high_priority_only {
        growell_patch::dedupe_arch($facts['pe_patch']['security_package_updates'])
      } elsif !$high_priority_only {
        growell_patch::dedupe_arch($facts['pe_patch']['package_updates'])
      } else {
        []
      },
      default => []
    }
    $high_prio_updates = $_kern ? {
      'windows' => $facts['pe_patch']['missing_update_kbs'].filter |$item| { $item in $high_priority_list },
      'linux'   => growell_patch::dedupe_arch($facts['pe_patch']['package_updates'].filter |$item| { $item in $high_priority_list }),
      default   => []
    }
  }
  else {
    $available_updates = []
    $high_prio_updates = []
  }

  # Allow self-service to override the configured blocklist
  if ($facts[$_override_fact]) {
    if ('blocklist' in $facts[$_override_fact]) {
      $selected_blocklist      = $facts[$_override_fact]['blocklist']['list']
      $selected_blocklist_mode = $facts[$_override_fact]['blocklist']['mode']
    } else {
      $selected_blocklist      = $blocklist
      $selected_blocklist_mode = $blocklist_mode
    }
  } else {
    $selected_blocklist      = $blocklist
    $selected_blocklist_mode = $blocklist_mode
  }

  # Determine which updates should get installed if any
  case $allowlist.count {
    0: {
      case $selected_blocklist_mode {
        'strict': {
          $_updates_to_install          = $available_updates.filter |$item| { !($item in $selected_blocklist) }
          $high_prio_updates_to_install = $high_prio_updates.filter |$item| { !($item in $selected_blocklist) }
        }
        'fuzzy': {
          $_updates_to_install          = growell_patch::fuzzy_filter($available_updates, $selected_blocklist)
          $high_prio_updates_to_install = growell_patch::fuzzy_filter($high_prio_updates, $selected_blocklist)
        }
        default: {
          fail("${selected_blocklist_mode} is an unsupported blocklist_mode")
        }
      }
      if ($_is_patchday and $_is_high_prio_patch_day) {
        $updates_to_install = $_updates_to_install.filter |$item| { !($item in $high_prio_updates_to_install) }
      } else {
        $updates_to_install = $_updates_to_install
      }
    }
    default: {
      $allowlisted_updates  = $available_updates.filter |$item| { $item in $allowlist }
      case $selected_blocklist_mode {
        'strict': {
          $_updates_to_install          = $allowlisted_updates.filter |$item| { !($item in $selected_blocklist) }
          $high_prio_updates_to_install = $high_prio_updates.filter |$item| { !($item in $selected_blocklist) }
        }
        'fuzzy': {
          $_updates_to_install          = growell_patch::fuzzy_filter($allowlisted_updates, $selected_blocklist)
          $high_prio_updates_to_install = growell_patch::fuzzy_filter($high_prio_updates, $selected_blocklist)
        }
        default: {
          fail("${selected_blocklist_mode} is an unsupported blocklist_mode")
        }
      }
      if ($_is_patchday and $_is_high_prio_patch_day) {
        $updates_to_install = $_updates_to_install.filter |$item| { !($item in $high_prio_updates_to_install) }
      } else {
        $updates_to_install = $_updates_to_install
      }
    }
  }

  # create the blocklist assuming we want to fuzzy match
  $_blocklist = $selected_blocklist_mode == 'fuzzy' ? {
    true    => growell_patch::fuzzy_match($available_updates, $selected_blocklist),
    default => $selected_blocklist,
  }

  ## Start of debug stuff
  notify { "process_groups     => ${result}": }
  notify { "available_updates  => ${available_updates}": }
  notify { "high_prio_updates  => ${high_prio_updates}": }
  notify { "updates_to_install => ${updates_to_install}": }
  notify { "_blocklist         => ${_blocklist}": }
  #File <| title == 'patching_configuration.json' |> {
  #  show_diff => true,
  #}
  ## End of debug stuff

  #if ($run_as_plan) {
  #  # These file resources use Deferred functions normally, which do not play nicely in apply blocks
  #  File <| title == 'Patching as Code - Save Patch Run Info' |> {
  #    content                 => patching_as_code::last_run($updates_to_install.unique, []),
  #  }
  #  File <| title == 'Patching as Code - Save High Priority Patch Run Info' |> {
  #    content                 => patching_as_code::high_prio_last_run($high_prio_updates_to_install.unique, []),
  #  }
  #}

  # Determine the states of the pre/post scripts based on operating system
  case $_kern {
    'linux': {
      $_script_base            = '/opt/puppetlabs/pe_patch'
      $_pre_patch_script_path  = "${_script_base}/pre_patch_script.sh"
      $_post_patch_script_path = "${_script_base}/post_patch_script.sh"
      $_pre_reboot_script_path = "${_script_base}/pre_reboot_script.sh"
      $_pre_check_script_path  = "${_script_base}/pre_check_script.sh"
      $_post_check_script_path = "${_script_base}/post_check_script.sh"
      $_fact_file              = 'pe_patch_fact_generation.sh'
      $_cmd_path               = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/puppetlabs/bin'
      $_common_present_args = {
        ensure => present,
        mode   => '0700',
        owner  => 'root',
        group  => 'root',
      }

      # override the fact generation file in order to support dnf for Redhat
      File <| title == "${_script_base}/${_fact_file}" |> {
        content => epp("${module_name}/${_fact_file}.epp", { 'environment' => $environment })
      }

      # Optionally pin the package if it occurs in the blocklist
      if ($pin_blocklist and $_blocklist.size > 0) or ($pin_blocklist and $facts['pe_patch']['pinned_packages'].size > 0) {
        if $_after_patch_window or $_after_high_prio_patch_window {
          # locks should be removed after the patch window
          $_to_unpin = $blocklist_mode == 'fuzzy' ? {
            true    => growell_patch::fuzzy_match($facts['pe_patch']['pinned_packages'], $blocklist),
            default => $blocklist
          }

          case $facts['package_provider'] {
            'apt': {
              apt::mark { $_to_unpin:
                setting => 'unhold',
                notify  => [Exec['pe_patch::exec::fact'], Exec['pe_patch::exec::fact_upload']],
              }
            }
            'dnf', 'yum': {
              $_to_unpin.each |$pin| {
                yum::versionlock { $pin.split(':')[0]:
                  ensure  => absent,
                  version => '*',
                  release => '*',
                  epoch   => 0,
                  notify  => [Exec['pe_patch::exec::fact'], Exec['pe_patch::exec::fact_upload']],
                }
              }
            }
            'zypper': {
              $_to_unpin.each |$pin| {
                exec { "${module_name}-removelock-${pin}":
                  command => "zypper removelock ${pin}",
                  path    => $_cmd_path,
                  notify  => [Exec['pe_patch::exec::fact'], Exec['pe_patch::exec::fact_upload']],
                }
              }
            }
            default: {
              fail("${module_name} currently does not support pinning ${facts['package_provider']} packages")
            }
          }
        } elsif ($run_as_plan) {
          # When running as a plan don't pin/unpin the blocklist
          notify { 'pinning the packages is not supported when running as a plan': }
        } elsif ($_is_patchday or $_is_high_prio_patch_day) {
          # locks should be created before the patch window
          case $facts['package_provider'] {
            'apt': {
              apt::mark { $_blocklist:
                setting => 'hold',
                notify  => [Exec['pe_patch::exec::fact'], Exec['pe_patch::exec::fact_upload']],
              }
            }
            'dnf', 'yum': {
              yum::versionlock { $_blocklist:
                ensure  => present,
                version => '*',
                release => '*',
                epoch   => 0,
                notify  => [Exec['pe_patch::exec::fact'], Exec['pe_patch::exec::fact_upload']],
              }
            }
            'zypper': {
              $_blocklist.each |$pin| {
                exec { "${module_name}-addlock-${pin}":
                  command => "zypper addlock ${pin}",
                  path    => $_cmd_path,
                  notify  => [Exec['pe_patch::exec::fact'], Exec['pe_patch::exec::fact_upload']],
                }
              }
            }
            default: {
              fail("${module_name} currently does not support pinning ${facts['package_provider']} packages")
            }
          }
        }
      }

      # Determine whats needed for pre_patch_script
      if $facts["${module_name}_scripts"]['pre_patch_script'] {
        $_pre_patch_commands = {
          'pre_patch_script' => {
            'command' => $_pre_patch_script_path,
            'path'    => $_cmd_path,
          },
        }
        $_pre_patch_file_args = $_common_present_args
      } else {
        $_pre_patch_commands = {}
        $_pre_patch_file_args = {
          ensure => absent,
        }
      }

      # Determine whats needed for post_patch_script
      if $facts["${module_name}_scripts"]['post_patch_script'] {
        $_post_patch_commands = {
          'post_patch_script' => {
            'command' => $_post_patch_script_path,
            'path'    => $_cmd_path,
          },
        }
        $_post_patch_file_args = $_common_present_args
      } else {
        $_post_patch_commands = {}
        $_post_patch_file_args = {
          ensure => absent,
        }
      }

      # Determine whats needed for pre_reboot_script
      if $pre_reboot_script == undef {
        $_pre_reboot_commands = {}
        $_pre_reboot_file_args = {
          ensure => absent,
        }
      } else {
        $_pre_reboot_commands = {
          'pre_reboot_script' => {
            'command' => $_pre_reboot_script_path,
            'path'    => $_cmd_path,
          },
        }
        $_pre_reboot_file_args = stdlib::merge(
          $_common_present_args,
          { source => "puppet:///modules/${module_name}/${pre_reboot_script}" }
        )
      }

      # Determine whats needed for pre_check_script
      if $pre_check_script == undef {
        $_pre_check_file_args = {
          ensure => absent,
        }
      } else {
        $_pre_check_file_args = stdlib::merge(
          $_common_present_args,
          {
            source => "puppet:///modules/${module_name}/${pre_check_script}",
          }
        )
        if (($_is_patchday or $_is_high_prio_patch_day) and ($_in_patch_window or $_in_high_prio_patch_window)) {
          if $run_as_plan {
            $_needs_ran = true
          } else {
            if $facts['growell_patch_report'].dig('pre_check') {
              $cur = growell_patch::within_cur_month($facts['growell_patch_report']['pre_check']['timestamp'])
              if $cur {
                if $facts['growell_patch_report']['pre_check']['status'] == 'success' {
                  if $_super_tuesday_end > Timestamp($facts['growell_patch_report']['pre_check']['timestamp']) {
                    $_needs_ran = true
                  } else {
                    $_needs_ran = false
                  }
                } else {
                  $needs_ran = true
                }
              } else {
                $_needs_ran = true
              }
            } else {
              $_needs_ran = true
            }
          }
          $_com_pre_check_script = {
            'command' => $_pre_check_script_path,
            'path'    => $_cmd_path,
            'before'  => Class["${module_name}::${_kern}::patchday"],
            'tag'     => ['growell_patch_pre_patching', 'growell_patch_pre_check'],
            'require' => File['pre_check_script'],
          }

          if ($updates_to_install.count > 0) {
            if $_needs_ran {
              $precheck_report_base = 'Growell_patch - Pre Check'
              $precheck_failure_data = stdlib::to_json(
                {
                  'pre_check' => {
                    'status'    => 'failed',
                    'timestamp' => Timestamp.new(),
                  }
                }
              )
              exec { "${precheck_report_base} - failed":
                command  => "${report_script_loc} -d '${precheck_failure_data}'",
                schedule => 'Growell_patch - Patch Window',
                before   => Exec['pre_check_script'],
                tag      => ['growell_patch_pre_check'],
              }

              exec { 'pre_check_script':
                *        => $_com_pre_check_script,
                schedule => 'Growell_patch - Patch Window',
              }

              $precheck_success_data = stdlib::to_json(
                {
                  'pre_check' => {
                    'status'    => 'success',
                    'timestamp' => Timestamp.new(),
                  }
                }
              )

              exec { "${precheck_report_base} - success":
                command     => "${report_script_loc} -d '${precheck_success_data}'",
                refreshonly => true,
                subscribe   => Exec['pre_check_script'],
                schedule    => 'Growell_patch - Patch Window',
                tag         => ['growell_patch_pre_check'],
              }
            }
          }
          if ($high_prio_updates_to_install.count > 0) {
            if $_needs_ran {
              $precheck_report_base = 'Growell_patch - High Priority Pre Check'
              $precheck_failure_data = stdlib::to_json(
                {
                  'pre_check' => {
                    'status'    => 'failed',
                    'timestamp' => Timestamp.new(),
                  }
                }
              )
              exec { "${precheck_report_base} - failed":
                command  => "${report_script_loc} -d '${precheck_failure_data}'",
                schedule => 'Growell_patch - High Priority Patch Window',
                before   => Exec['pre_check_script (High Priority)'],
                tag      => ['growell_patch_pre_check'],
              }

              exec { 'pre_check_script (High Priority)':
                *        => $_com_pre_check_script,
                schedule => 'Growell_patch - High Priority Patch Window',
              }

              $precheck_success_data = stdlib::to_json(
                {
                  'pre_check' => {
                    'status'    => 'success',
                    'timestamp' => Timestamp.new(),
                  }
                }
              )

              exec { "${precheck_report_base} - success":
                command     => "${report_script_loc} -d '${precheck_success_data}'",
                refreshonly => true,
                subscribe   => Exec['pre_check_script (High Priority)'],
                schedule    => 'Growell_patch - High Priority Patch Window',
                tag         => ['growell_patch_pre_check'],
              }

            }
          }
        }
      }

      # Determine whats needed for post_check_script
      if $post_check_script == undef {
        $_post_check_file_args = {
          ensure => absent,
        }
      } else {
        $_post_check_file_args = stdlib::merge(
          $_common_present_args,
          {
            source => "puppet:///modules/${module_name}/${post_check_script}",
          }
        )
        if ($_is_patchday or $_is_high_prio_patch_day) {
          $_com_post_check_script = {
            'command' => $_post_check_script_path,
            'path'    => $_cmd_path,
            'require' => [File['post_check_script'], Anchor['growell_patch::post']],
            'tag'     => ['growell_patch_post_patching', "${module_name}_post_check"],
          }
          # When running as a plan we need to check if the post reboot occured
          if ($run_as_plan and $facts['growell_patch_report'].dig('post_reboot')) {
            if $_in_patch_window {
              class { "${module_name}::post_check":
                priority          => 'normal',
                exec_args         => $_com_post_check_script,
                stage             => "${module_name}_after_post_reboot",
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end,
              }
            }
            if $_in_high_prio_patch_window {
              class { "${module_name}::post_check":
                priority          => 'high',
                exec_args         => $_com_post_check_script,
                stage             => "${module_name}_after_post_reboot",
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end,
              }
            }
          } elsif $run_as_plan == false {
            if $_in_patch_window {
              class { "${module_name}::post_check":
                priority          => 'normal',
                exec_args         => $_com_post_check_script,
                stage             => "${module_name}_after_post_reboot",
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end,
              }
            }
            if $_in_high_prio_patch_window {
              class { "${module_name}::post_check":
                priority          => 'high',
                exec_args         => $_com_post_check_script,
                stage             => "${module_name}_after_post_reboot",
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end,
              }
            }
          }
        }
      }
    }
    'windows': {
      $_script_base            = 'C:/ProgramData/PuppetLabs/pe_patch'
      $_pre_patch_script_path  = "${_script_base}/pre_patch_script.ps1"
      $_post_patch_script_path = "${_script_base}/post_patch_script.ps1"
      $_pre_reboot_script_path = "${_script_base}/pre_reboot_script.ps1"
      $_pre_check_script_path  = "${_script_base}/pre_check_script.ps1"
      $_post_check_script_path = "${_script_base}/post_check_script.ps1"
      $_common_present_args = {
        ensure => present,
        mode   => '0770',
      }

      # make sure the PSWindowsUpdate powershell module gets installed before patchday
      include growell_patch::wu

      # Make sure wsus server is used assuming wsus_url is set
      #
      # https://github.com/vFense/vFenseAgent-win/wiki/Registry-keys-for-configuring-Automatic-Updates-&-WSUS
      $_base_reg = 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate'
      $_au_base_reg = "${_base_reg}\\AU"
      if $wsus_url == undef {
        registry_value { "${_base_reg}\\WUServer":
          ensure => absent,
          #          type   => 'string',
          #          data   => $wsus_url,
          #          tag    => ["${module_name}-WUServer", "${module_name}_reg"],
          #before => Class["${module_name}::${_kern}::patchday"],
          notify => Service['wuauserv'],
        }

        # We need to not conflict with other modules that manage wsus, for example 'puppetlabs/wsus_client'
        if (defined(Registry_value['UseWUServer']) or defined(Registry_value["${_au_base_reg}\\UseWUServer"])) {
          Registry_value <| title == 'UseWUServer' or title == "${_au_base_reg}\\UseWUServer" |> {
            ensure => absent,
            #data   => 1,
            tag    => ["${module_name}-UseWUServer", "${module_name}_reg"],
            #before => Class["${module_name}::${_kern}::patchday"],
            notify => Service['wuauserv'],
          }
        } else {
          registry_value { "${_au_base_reg}\\UseWUServer":
            ensure => absent,
            #   type   => dword,
            #   data   => 1,
            tag    => ["${module_name}-UseWUServer", "${module_name}_reg"],
            #before => Class["${module_name}::${_kern}::patchday"],
            notify => Service['wuauserv'],
          }
        }

        unless defined(Service['wuauserv']) {
          # The windows update service needs be restarted in the event of registry changes
          # Thus it needs to be in the catalog for our registry_value's to notify
          service { 'wuauserv':
            enable => true,
            ensure => running,
          }
        }
      } else {
        registry_value { "${_base_reg}\\WUServer":
          ensure => present,
          type   => 'string',
          data   => $wsus_url,
          tag    => ["${module_name}-WUServer", "${module_name}_reg"],
          #before => Class["${module_name}::${_kern}::patchday"],
          notify => Service['wuauserv'],
        }

        # We need to not conflict with other modules that manage wsus, for example 'puppetlabs/wsus_client'
        if (defined(Registry_value['UseWUServer']) or defined(Registry_value["${_au_base_reg}\\UseWUServer"])) {
          Registry_value <| title == 'UseWUServer' or title == "${_au_base_reg}\\UseWUServer" |> {
            data   => 1,
            tag    => ["${module_name}-UseWUServer", "${module_name}_reg"],
            #before => Class["${module_name}::${_kern}::patchday"],
            notify => Service['wuauserv'],
          }
        } else {
          registry_value { "${_au_base_reg}\\UseWUServer":
            ensure => present,
            type   => dword,
            data   => 1,
            tag    => ["${module_name}-UseWUServer", "${module_name}_reg"],
            #before => Class["${module_name}::${_kern}::patchday"],
            notify => Service['wuauserv'],
          }
        }

        unless defined(Service['wuauserv']) {
          # The windows update service needs be restarted in the event of registry changes
          # Thus it needs to be in the catalog for our registry_value's to notify
          service { 'wuauserv':
            enable => true,
            ensure => running,
          }
        }

        # Ensure wsus settings get applied before any prefetch
        Registry_value <| tag == "${module_name}_reg" |> ->
        Exec <| tag == "${module_name}-prefetch-kb" |>
      }

      # Optionally hide the KB if it occurs in the blocklist
      if ($pin_blocklist and $_blocklist.size > 0) {
        if $blocklist_mode == 'fuzzy' {
          # Windows does a really good job at hiding them and we need a sane way to track whats been hidden
          fail("${module_name} does not support fuzzy blocklist on windows when ${module_name}::pin_blocklist = true")
        }

        if ($_after_patch_window or $_after_high_prio_patch_window) {
          # KB's should be unhidden after the patch window
          $_blocklist.each |$kb| {
            unless ($kb in $available_updates) {
              # if pe_patch detects its an available update we can skip the powershell check
              exec { "${module_name}-unhide-${kb}":
                command  => "Unhide-WindowsUpdate -KBArticleID '${kb}' -AcceptAll",
                unless   => epp("${module_name}/kb_is_unhidden.ps1.epp", { 'kb' => $kb }),
                provider => 'powershell',
                before   => Class["${module_name}::${_kern}::patchday"],
                notify   => [Exec['pe_patch::exec::fact'], Exec['pe_patch::exec::fact_upload']],
              }
            }
          }
        } elsif ($run_as_plan) {
          # When running as a plan don't hide KB's
          notify { 'Hiding the KBs is not supported when running as a plan': }
        } elsif ($_is_patchday or $_is_high_prio_patch_day) {
          # KB's should be hidden before the patch window
          $_blocklist.each |$kb| {
            exec { "${module_name}-hide-${kb}":
              command  => "Hide-WindowsUpdate -KBArticleID '${kb}' -AcceptAll",
              unless   => epp("${module_name}/kb_is_hidden.ps1.epp", { 'kb' => $kb }),
              provider => 'powershell',
              before   => Class["${module_name}::${_kern}::patchday"],
              notify   => [Exec['pe_patch::exec::fact'], Exec['pe_patch::exec::fact_upload']],
            }
          }
        }
      }

      # Prefetch update(s) if a prefetch window is defined and we are within said window
      unless ($windows_prefetch_before == undef) {
        if ($_in_prefetch_window or $_in_high_prio_prefetch_window) {
          # Need to determine what patches need to be downloaded and passed to Get-WindowsUpdate
          # ex:
          #  Get-WindowsUpdate -KBArticleID "KB5044281" -Download -AcceptAll
          $updates_to_install.each |String $kb| {
            exec { "prefetch ${kb}":
              command  => "Get-WindowsUpdate -KBArticleID ${kb} -Download -AcceptAll",
              provider => 'powershell',
              unless   => epp("${module_name}/kb_is_prefetched.ps1.epp", { 'kb' => $kb }),
              timeout  => 14400,
              tag      => ["${module_name}-prefetch-kb"],
            }
            $prefetch_data = stdlib::to_json(
              {
                'prefetch_kbs' => {
                  $kb => Timestamp.new(),
                }
              }
            )

            exec { "${kb} - Prefetch":
              command  => "${report_script_loc} -d '${prefetch_data}'",
              require  => Exec["prefetch ${kb}"],
            }
          }
        }
      }

      # Determine whats needed for pre_patch_script
      if $facts["${module_name}_scripts"]['pre_patch_script'] {
        $_pre_patch_commands = {
          'pre_patch_script' => {
            'command' => $_pre_patch_script_path,
            'provider' => 'powershell',
          },
        }
        $_pre_patch_file_args = $_common_present_args
      } else {
        $_pre_patch_commands = {}
        $_pre_patch_file_args = {
          ensure => absent,
        }
      }

      # Determine whats needed for post_patch_script
      if $facts["${module_name}_scripts"]['post_patch_script'] {
        $_post_patch_commands = {
          'post_patch_script' => {
            'command' => $_post_patch_script_path,
            'provider' => 'powershell',
          },
        }
        $_post_patch_file_args = $_common_present_args
      } else {
        $_post_patch_commands = {}
        $_post_patch_file_args = {
          ensure => absent,
        }
      }

      # Determine whats needed for pre_reboot_script
      if $pre_reboot_script == undef {
        $_pre_reboot_commands = {}
        $_pre_reboot_file_args = {
          ensure => absent,
        }
      } else {
        $_pre_reboot_commands = {
          'pre_reboot_script' => {
            'command'  => $_pre_reboot_script_path,
            'provider' => 'powershell',
          },
        }
        $_pre_reboot_file_args = stdlib::merge(
          $_common_present_args,
          {
            source => "puppet:///modules/${module_name}/${pre_reboot_script}"
          }
        )
      }

      # Determine whats needed for pre_check_script
      if $pre_check_script == undef {
        $_pre_check_file_args = {
          ensure => absent,
        }
      } else {
        $_pre_check_file_args = stdlib::merge(
          $_common_present_args,
          {
            source => "puppet:///modules/${module_name}/${pre_check_script}",
          }
        )
        if (($_is_patchday or $_is_high_prio_patch_day) and ($_in_patch_window or $_in_high_prio_patch_window)) {
          if $facts['growell_patch_report'].dig('pre_check') {
            $cur = growell_patch::within_cur_month($facts['growell_patch_report']['pre_check']['timestamp'])
            if $cur {
              if $facts['growell_patch_report']['pre_check']['status'] == 'success' {
                $_needs_ran = Timestamp.new() < Timestamp($facts['growell_patch_report']['pre_check']['timestamp'])
              } else {
                $_needs_ran = true
              }
            } else {
              $_needs_ran = true
            }
          } else {
            $_needs_ran = true
          }
          $_com_pre_check_script = {
            'command'  => $_pre_check_script_path,
            'provider' => powershell,
            'require'  => File['pre_check_script'],
            'before'   => Class["${module_name}::${_kern}::patchday"],
            'tag'      => ['growell_patch_pre_patching'],
          }
          if ($updates_to_install.count > 0) {
            if $_needs_ran {
              $precheck_report_base = 'Growell_patch - Pre Check'
              $precheck_failure_data = stdlib::to_json(
                {
                  'pre_check' => {
                    'status'    => 'failed',
                    'timestamp' => Timestamp.new(),
                  }
                }
              )
              exec { "${precheck_report_base} - failed":
                command  => "${report_script_loc} -d '${precheck_failure_data}'",
                schedule => 'Growell_patch - Patch Window',
                before   => Exec['pre_check_script'],
                tag      => ['growell_patch_pre_check'],
              }
              exec { 'pre_check_script':
                *        => $_com_pre_check_script,
                schedule => 'Growell_patch - Patch Window',
              }
              $precheck_success_data = stdlib::to_json(
                {
                  'pre_check' => {
                    'status'    => 'success',
                    'timestamp' => Timestamp.new(),
                  }
                }
              )

              exec { "${precheck_report_base} - success":
                command     => "${report_script_loc} -d '${precheck_success_data}'",
                refreshonly => true,
                subscribe   => Exec['pre_check_script'],
                schedule    => 'Growell_patch - Patch Window',
                tag         => ['growell_patch_pre_check'],
              }
            }
          }
          if ($high_prio_updates_to_install.count > 0) {
            if $_needs_ran {
              $precheck_report_base = 'Growell_patch - High Priority Pre Check'
              $precheck_failure_data = stdlib::to_json(
                {
                  'pre_check' => {
                    'status'    => 'failed',
                    'timestamp' => Timestamp.new(),
                  }
                }
              )
              exec { "${precheck_report_base} - failed":
                command  => "${report_script_loc} -d '${precheck_failure_data}'",
                schedule => 'Growell_patch - High Priority Patch Window',
                before   => Exec['pre_check_script (High Priority)'],
                tag      => ['growell_patch_pre_check'],
              }

              exec { 'pre_check_script (High Priority)':
                *        => $_com_pre_check_script,
                schedule => 'Growell_patch - High Priority Patch Window',
              }

              $precheck_success_data = stdlib::to_json(
                {
                  'pre_check' => {
                    'status'    => 'success',
                    'timestamp' => Timestamp.new(),
                  }
                }
              )

              exec { "${precheck_report_base} - success":
                command     => "${report_script_loc} -d '${precheck_success_data}'",
                refreshonly => true,
                subscribe   => Exec['pre_check_script (High Priority)'],
                schedule    => 'Growell_patch - High Priority Patch Window',
                tag         => ['growell_patch_pre_check'],
              }
            }
          }
        }
      }

      # Determine whats needed for post_check_script
      if $post_check_script == undef {
        $_post_check_file_args = {
          ensure => absent,
        }
      } else {
        $_post_check_file_args = stdlib::merge(
          $_common_present_args,
          {
            source  => "puppet:///modules/${module_name}/${post_check_script}",
          }
        )
        if ($_is_patchday or $_is_high_prio_patch_day) {
          $_com_post_check_script = {
            'command'  => $_post_check_script_path,
            'provider' => powershell,
            'require'  => [File['post_check_script'], Anchor['growell_patch::post']],
            'tag'      => ['growell_patch_post_patching', "${module_name}_post_check"],
          }
          # When running as a plan we need to check if the post reboot occured
          if ($run_as_plan and $facts['growell_patch_report'].dig('post_reboot')) {
            if $_in_patch_window {
              class { "${module_name}::post_check":
                priority          => 'normal',
                exec_args         => $_com_post_check_script,
                stage             => "${module_name}_after_post_reboot",
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end,
              }
            }
            if $_in_high_prio_patch_window {
              class { "${module_name}::post_check":
                priority          => 'high',
                exec_args         => $_com_post_check_script,
                stage             => "${module_name}_after_post_reboot",
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end,
              }
            }
          } elsif $run_as_plan == false {
            if $_in_patch_window {
              class { "${module_name}::post_check":
                priority          => 'normal',
                exec_args         => $_com_post_check_script,
                stage             => "${module_name}_after_post_reboot",
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end
              }
            }
            if $_in_high_prio_patch_window {
              class { "${module_name}::post_check":
                priority          => 'high',
                exec_args         => $_com_post_check_script,
                stage             => "${module_name}_after_post_reboot",
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end,
              }
            }
          }
        }
      }
    }
    default: { fail("Unsupported OS: ${facts['kernel']}") }
  }

  # Manage the various pre/post scripts
  file {
    default:
      require => File[$_script_base],
      ;
    'pre_patch_script':
      path => $_pre_patch_script_path,
      *    => $_pre_patch_file_args,
      ;
    'post_patch_script':
      path => $_post_patch_script_path,
      *    => $_post_patch_file_args,
      ;
    'pre_reboot_script':
      path => $_pre_reboot_script_path,
      *    => $_pre_reboot_file_args,
      ;
    'pre_check_script':
      path => $_pre_check_script_path,
      *    => $_pre_check_file_args,
      ;
    'post_check_script':
      path => $_post_check_script_path,
      *    => $_post_check_file_args,
      ;
  }

  # Make sure if the fact gets refreshed, it happens before upload
  Exec['pe_patch::exec::fact'] -> Exec['pe_patch::exec::fact_upload']

  # Write local state file for config reporting and reuse in plans
  file { "${module_name}_configuration.json":
    ensure    => file,
    path      => "${facts['puppet_vardir']}/../../facter/facts.d/${module_name}_configuration.json",
    content   => to_json_pretty( { # lint:ignore:manifest_whitespace_opening_brace_before
      "${module_name}_config" => {
        allowlist                 => $allowlist,
        blocklist                 => $_blocklist,
        high_priority_list        => $high_priority_list,
        enable_patching           => $enable_patching,
        patch_group               => $_patch_group,
        patch_schedule            => if $_active_pg in ['always', 'never'] {
          { $_active_pg => 'N/A' }
        } else {
          $_patch_schedule.filter |$item| { $item[0] in $_patch_group }
        },
        high_priority_patch_group => $high_priority_patch_group,
        post_patch_commands       => $_post_patch_commands,
        pre_patch_commands        => $_pre_patch_commands,
        pre_reboot_commands       => $_pre_reboot_commands,
        patch_on_metered_links    => $patch_on_metered_links,
        security_only             => $security_only,
        unsafe_process_list       => $unsafe_process_list,
      },
      }, false),
      show_diff => false,
  }

  # Pre reboot
  $pre_reboot = case $_pre_reboot {
    'always': { true }
    'never': { false }
    'ifneeded': { true }
    default: { false }
  }
  $high_prio_pre_reboot = case $_high_prio_pre_reboot {
    'always': { true }
    'never': { false }
    'ifneeded': { true }
    default: { false }
  }
  $post_reboot = case $_post_reboot {
    'always': { true }
    'never': { false }
    'ifneeded': { true }
    default: { false }
  }
  $post_reboot_if_needed = case $_post_reboot {
    'ifneeded': { true }
    default: { false }
  }
  $high_prio_post_reboot = case $_high_prio_post_reboot {
    'always': { true }
    'never': { false }
    'ifneeded': { true }
    default: { false }
  }
  $high_prio_post_reboot_if_needed = case $_high_prio_post_reboot {
    'ifneeded': { true }
    default: { false }
  }

  if ($_is_patchday and $_in_patch_window) or ($_is_high_prio_patch_day and $_in_high_prio_patch_window) {
    # Only deal with pre_reboot if this is a normal puppet run. if being ran as a plan we handle it elsewhere
    unless $run_as_plan {
      # Perform pending reboots pre-patching, except if this is a high prio only run
      if $enable_patching and !$high_priority_only {
        if $pre_reboot and $_is_patchday {
          # Reboot the node first if a reboot is already pending
          case $_kern {
            /(windows|linux)/: {
              class { 'growell_patch::pre_reboot':
                priority          => 'normal',
                reboot_type       => $_pre_reboot,
                schedule          => 'Growell_patch - Patch Window',
                before            => Anchor['growell_patch::start'],
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end,
              }
            }
            default: {
              fail('Unsupported operating system for Growell_patch!')
            }
          }
        }
        if $high_prio_pre_reboot and $_is_high_prio_patch_day and
        ($high_prio_updates_to_install.count > 0) {
          # Reboot the node first if a reboot is already pending
          case $_kern {
            /(windows|linux)/: {
              class { 'growell_patch::pre_reboot':
                priority          => 'high',
                reboot_type       => $_high_prio_pre_reboot,
                schedule          => 'Growell_patch - High Priority Patch Window',
                before            => Anchor['growell_patch::start'],
                report_script_loc => $report_script_loc,
                run_as_plan       => $run_as_plan,
                super_tuesday_end => $_super_tuesday_end,
              }
            }
            default: {
              fail("Unsupported operating system for Growell_patch!")
            }
          }
        }
      }
    }
    anchor { "${module_name}::start": } #lint:ignore:anchor_resource

    if $enable_patching == true {
      if (($patch_on_metered_links == true) or (! $facts['metered_link'] == true)) and (! $facts['patch_unsafe_process_active'] == true) {
        # Check if we installed updates this month, if so we've already patched
        if $run_as_plan {
          $_patching_needs_ran = true
        } else {
          if $facts['growell_patch_report'].dig('updates_installed') {
            $cur_patching = growell_patch::within_cur_month($facts['growell_patch_report']['updates_installed']['timestamp'])
            if $cur_patching {
              if $_super_tuesday_end > Timestamp($facts['growell_patch_report']['updates_installed']['timestamp']) {
                $_patching_needs_ran = true
              } else {
                $_patching_needs_ran = false
              }
            } else {
              $_patching_needs_ran = true
            }
          } else {
            $_patching_needs_ran = true
          }
        }

        case $_kern {
          /(windows|linux)/: {
            # Run pre-patch commands if provided
            if ($updates_to_install.count > 0) {
              unless $_pre_patch_commands.empty {
                class { "${module_name}::pre_patch_script":
                  pre_patch_commands => $_pre_patch_commands,
                  priority           => 'normal',
                  report_script_loc  => $report_script_loc,
                  run_as_plan        => $run_as_plan,
                  super_tuesday_end  => $_super_tuesday_end,
                }
              }
            }
            if ($high_prio_updates_to_install.count > 0) {
              unless $_pre_patch_commands.empty {
                class { "${module_name}::pre_patch_script":
                  pre_patch_commands => $_pre_patch_commands,
                  priority           => 'high',
                  report_script_loc  => $report_script_loc,
                  run_as_plan        => $run_as_plan,
                  super_tuesday_end  => $_super_tuesday_end,
                }
              }
            }
            # Perform main patching run
            $patch_refresh_actions = $fact_upload ? {
              true  => [Exec['pe_patch::exec::fact'], Exec['pe_patch::exec::fact_upload']],
              false => Exec['pe_patch::exec::fact']
            }
            if ($updates_to_install.count + $high_prio_updates_to_install.count > 0 and $_patching_needs_ran) {
              # We need our own exec since patchday also notify's the exec it gets refreshed then
              notify { 'Growell_patch - Pre Update Fact':
                message  => 'Refreshing patching facts to ensure sources available',
                notify   => Exec["${module_name}::update_pe_patch_fact"],
                schedule => 'Growell_patch - Patch Window',
                require  => Anchor['growell_patch::start'],
              }
              case $_kern {
                'windows': {
                  $fact_dir  = 'C:/ProgramData/PuppetLabs/pe_patch'
                  $fact_file = 'pe_patch_fact_generation.ps1'
                  $fact_cmd  = "${fact_dir}/${fact_file}"
                  exec { "${module_name}::update_pe_patch_fact":
                    path        => 'C:/Windows/System32/WindowsPowerShell/v1.0',
                    refreshonly => true,
                    command     => "powershell -executionpolicy remotesigned -file ${fact_cmd}",
                    timeout     => $pe_patch::initial_fact_timeout,
                    notify      => Class["${module_name}::${_kern}::patchday"],
                  }
                }
                'linux': {
                  $fact_dir  = '/opt/puppetlabs/pe_patch'
                  $fact_file = 'pe_patch_fact_generation.sh'
                  $fact_cmd  = "${fact_dir}/${fact_file}"
                  exec { "${module_name}::update_pe_patch_fact":
                    command     => $fact_cmd,
                    user      => $pe_patch::patch_data_owner,
                    group     => $pe_patch::patch_data_group,
                    refreshonly => true,
                    require     => [
                      File[$fact_cmd],
                      File["${fact_dir}/reboot_override"]
                    ],
                    timeout     => $pe_patch::initial_fact_timeout,
                    notify      => Class["${module_name}::${_kern}::patchday"],
                  }
                }
              }

              class { "${module_name}::${_kern}::patchday":
                updates           => $updates_to_install.unique,
                high_prio_updates => $high_prio_updates_to_install.unique,
                install_options   => $install_options,
                report_script_loc => $report_script_loc,
                require           => Anchor['growell_patch::start'],
                before            => Anchor['growell_patch::post'],
              }
            }
            if ($updates_to_install.count > 0 and $_patching_needs_ran) {
              notify { 'Growell_patch - Update Fact':
                message  => 'Patches installed, refreshing patching facts...',
                notify   => $patch_refresh_actions,
                schedule => 'Growell_patch - Patch Window',
                before   => Anchor['growell_patch::post'],
                require  => Class["${module_name}::${_kern}::patchday"],
              }
            }
            if ($high_prio_updates_to_install.count > 0 and $_patching_needs_ran) {
              notify { 'Growell_patch - Update Fact (High Priority)':
                message  => 'Patches installed, refreshing patching facts...',
                notify   => $patch_refresh_actions,
                schedule => 'Growell_patch - High Priority Patch Window',
                before   => Anchor['growell_patch::post'],
                require  => Class["${module_name}::${_kern}::patchday"],
              }
            }
            anchor { 'growell_patch::post': } #lint:ignore:anchor_resource
            if ($post_reboot and $_is_patchday) or ($high_prio_post_reboot and ($high_prio_updates_to_install.count > 0)) { #lint:ignore:140chars
              # Only post_reboot if this is a normal puppet run. if being ran as a plan we handle it elsewhere
              unless $run_as_plan {
                # Reboot after patching (in later patch_reboot stage)
                if ($updates_to_install.count > 0) and $post_reboot {
                  class { 'growell_patch::post_reboot':
                    priority          => 'normal',
                    reboot_type       => $_post_reboot,
                    schedule          => 'Growell_patch - Patch Window',
                    stage             => "${module_name}_post_reboot",
                    report_script_loc => $report_script_loc,
                    run_as_plan       => $run_as_plan,
                    super_tuesday_end => $_super_tuesday_end,
                  }
                }
                if ($high_prio_updates_to_install.count > 0) and $high_prio_post_reboot {
                  class { 'growell_patch::post_reboot':
                    priority          => 'high',
                    reboot_type       => $_high_prio_post_reboot,
                    schedule          => 'Growell_patch - High Priority Patch Window',
                    stage             => "${module_name}_post_reboot",
                    report_script_loc => $report_script_loc,
                    run_as_plan       => $run_as_plan,
                    super_tuesday_end => $_super_tuesday_end,
                  }
                }

                #if ($updates_to_install.count > 0) and $post_reboot {
                #  class { 'growell_patch::reboot':
                #    reboot_if_needed  => $post_reboot_if_needed,
                #    schedule          => 'Growell_patch - Patch Window',
                #    stage             => "${module_name}_post_reboot",
                #    report_script_loc => $report_script_loc,
                #  }
                #}
                #if ($high_prio_updates_to_install.count > 0) and $high_prio_post_reboot {
                #  class { 'growell_patch::high_prio_reboot':
                #    reboot_if_needed => $high_prio_post_reboot_if_needed,
                #    schedule         => 'Growell_patch - High Priority Patch Window',
                #    stage            => "${module_name}_post_reboot",
                #  }
                #}
              }
              # Perform post-patching Execs
              if ($run_as_plan and $facts['growell_patch_report'].dig('post_reboot')) {
                # If running as a plan we need to check that the post_reboot actually happened
                if ($_in_patch_window and $post_reboot) {
                  unless $_post_patch_commands.empty {
                    class { "${module_name}::post_patch_script":
                      post_patch_commands => $_post_patch_commands,
                      priority            => 'normal',
                      stage               => "${module_name}_after_post_reboot",
                      report_script_loc   => $report_script_loc,
                      run_as_plan         => $run_as_plan,
                      super_tuesday_end   => $_super_tuesday_end,
                    }
                  }
                }
                if ($_in_high_prio_patch_window and $high_prio_post_reboot) {
                  unless $_post_patch_commands.empty {
                    class { "${module_name}::post_patch_script":
                      post_patch_commands => $_post_patch_commands,
                      priority            => 'high',
                      stage               => "${module_name}_after_post_reboot",
                      report_script_loc   => $report_script_loc,
                      run_as_plan         => $run_as_plan,
                      super_tuesday_end   => $_super_tuesday_end,
                    }
                  }
                }
              } elsif $run_as_plan == false {
                # This is a normal puppet run
                if ($_in_patch_window and $post_reboot) {
                  unless $_post_patch_commands.empty {
                    class { "${module_name}::post_patch_script":
                      post_patch_commands => $_post_patch_commands,
                      priority            => 'normal',
                      stage               => "${module_name}_after_post_reboot",
                      report_script_loc   => $report_script_loc,
                      run_as_plan         => $run_as_plan,
                      super_tuesday_end   => $_super_tuesday_end,
                    }
                  }
                }
                if ($_in_high_prio_patch_window and $high_prio_post_reboot) {
                  unless $_post_patch_commands.empty {
                    class { "${module_name}::post_patch_script":
                      post_patch_commands => $_post_patch_commands,
                      priority            => 'high',
                      stage               => "${module_name}_after_post_reboot",
                      report_script_loc   => $report_script_loc,
                      run_as_plan         => $run_as_plan,
                      super_tuesday_end   => $_super_tuesday_end,
                    }
                  }
                }
              }
              # Define pre-reboot Execs
              case $facts['kernel'].downcase() {
                'windows': {
                  $reboot_logic_provider = 'powershell'
                  $reboot_logic_onlyif   = $post_reboot_if_needed ? {
                    true  => "${facts['puppet_vardir']}/lib/${module_name}/pending_reboot.ps1",
                    false => if ($updates_to_install.count > 0) {
                      undef
                    } else {
                      "${facts['puppet_vardir']}/lib/${module_name}/pending_reboot.ps1"
                    }
                  }
                  $reboot_logic_onlyif_high_prio = $high_prio_post_reboot_if_needed ? {
                    true  => "${facts['puppet_vardir']}/lib/${module_name}/pending_reboot.ps1",
                    false => undef
                  }
                }
                'linux': {
                  $reboot_logic_provider = 'posix'
                  $reboot_logic_onlyif   = $post_reboot_if_needed ? {
                    true  => "/bin/sh ${facts['puppet_vardir']}/lib/${module_name}/pending_reboot.sh",
                    false => if ($updates_to_install.count > 0) {
                      undef
                    } else {
                      "/bin/sh ${facts['puppet_vardir']}/lib/${module_name}/pending_reboot.sh"
                    }
                  }
                  $reboot_logic_onlyif_high_prio = $high_prio_post_reboot_if_needed ? {
                    true  => "/bin/sh ${facts['puppet_vardir']}/lib/${module_name}/pending_reboot.sh",
                    false => undef
                  }
                }
                default: {
                  fail('Unsupported operating system for Growell_patch!')
                }
              }
              if $post_reboot and $_is_patchday and !$high_priority_only {
                $_pre_reboot_commands.each | $cmd, $cmd_opts | {
                  exec { "Growell_patch - Before reboot - ${cmd}":
                    *        => delete($cmd_opts, ['provider', 'onlyif', 'unless', 'require', 'before', 'schedule', 'tag']),
                    provider => $reboot_logic_provider,
                    onlyif   => $reboot_logic_onlyif,
                    require  => Anchor['growell_patch::post'],
                    schedule => 'Growell_patch - Patch Window',
                    tag      => ['growell_patch_pre_reboot'],
                  }
                }
              }
              if $high_prio_post_reboot and ($high_prio_updates_to_install.count > 0) {
                $_pre_reboot_commands.each | $cmd, $cmd_opts | {
                  exec { "Growell_patch - Before reboot (High Priority) - ${cmd}":
                    *        => delete($cmd_opts, ['provider', 'onlyif', 'unless', 'require', 'before', 'schedule', 'tag']),
                    provider => $reboot_logic_provider,
                    onlyif   => $reboot_logic_onlyif_high_prio,
                    require  => Anchor['growell_patch::post'],
                    schedule => 'Growell_patch - High Priority Patch Window',
                    tag      => ['growell_patch_pre_reboot'],
                  }
                }
              }
            } else {
              # Do not reboot after patching, just run post_patch commands if given
              if ($updates_to_install.count > 0) {
                $_post_patch_commands.each | $cmd, $cmd_opts | {
                  exec { "Growell_patch - After patching - ${cmd}":
                    *        => delete($cmd_opts, ['require', 'schedule', 'tag']),
                    require  => Anchor['growell_patch::post'],
                    schedule => 'Growell_patch - Patch Window',
                    tag      => ['growell_patch_post_patching'],
                  }
                }
              }
              if ($high_prio_updates_to_install.count > 0) {
                $_post_patch_commands.each | $cmd, $cmd_opts | {
                  exec { "Growell_patch - After patching (High Priority)- ${cmd}":
                    *        => delete($cmd_opts, ['require', 'schedule', 'tag']),
                    require  => Anchor['growell_patch::post'],
                    schedule => 'Growell_patch - High Priority Patch Window',
                    tag      => ['growell_patch_post_patching'],
                  }
                }
              }
            }
          }
          default: {
            fail('Unsupported operating system for Growell_patch!')
          }
        }
      } else {
        if $facts['metered_link'] == true {
          notice("Puppet is skipping installation of patches on ${trusted['certname']} due to the current network link being metered.")
        }
        if $facts['patch_unsafe_process_active'] == true {
          notice("Puppet is skipping installation of patches on ${trusted['certname']} because a process is active that is unsafe for patching.") #lint:ignore:140chars
        }
      }
    }
  }
}
