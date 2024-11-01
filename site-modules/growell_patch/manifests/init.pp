# @summary A wrapper around the puppetlabs/patching_as_code, which itself is a wrapper
#   around puppetlabs/pe_patch
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
# @param pre_check_script
# @param post_check_script
# @param high_priority_patch_group
#
# @example
#   include growell_patch
class growell_patch (
  Hash[String[1], Growell_patch::Patch_schedule] $patch_schedule, Variant[String[1], Array[String[1]]]           $patch_group,
  Boolean                                        $enable_patching           = true,
  Boolean                                        $high_priority_only        = false,
  Boolean                                        $security_only             = false,
  Enum['strict', 'fuzzy']                        $blocklist_mode            = 'strict',
  Optional[String[1]]                            $pre_patch_script          = undef,
  Optional[String[1]]                            $post_patch_script         = undef,
  Optional[String[1]]                            $pre_reboot_script         = undef,
  Optional[Array]                                $install_options           = undef,
  Array                                          $allowlist                 = [],
  Array                                          $blocklist                 = [],
  Array                                          $high_priority_list        = [],
  Optional[String[1]]                            $pre_check_script          = undef,
  Optional[String[1]]                            $post_check_script         = undef,
  Optional[String[1]]                            $high_priority_patch_group = undef,
  Optional[String[1]]                            $windows_prefetch_before   = undef,
) {
  # Convert our custom schedule into the form expected by patching_as_code.
  #
  # Using the growell_patch::patchday function we are able to determine the 'day_of_week'
  #   and 'count_of_week' based off of our 'day', 'week', and 'offset' params.
  $_patch_schedule = $patch_schedule.reduce({}) |$memo, $x| {
    $memo + {
      $x[0] => {
        'day_of_week'   => growell_patch::patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['day_of_week'],
        'count_of_week' => growell_patch::patchday($x[1]['day'], $x[1]['week'], $x[1]['offset'])['count_of_week'],
        'hours'         => $x[1]['hours'],
        'max_runs'      => $x[1]['max_runs'],
        'reboot'        => $x[1]['reboot'],
      }
    }
  }

  # Process the configured groups so we can determine the proper outcome
  $result = growell_patch::process_groups($patch_group, $_patch_schedule, $high_priority_patch_group, $windows_prefetch_before)
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

  # this is for testing
  #  class { 'puppet_agent':
  #    config => [{ section => 'main', setting => 'splay', value => 'true' },{ section => 'main', setting => 'runtimeout', value => '1234' }]
  #  }

  # Configure the agents runtimeout accordingly
  if ($_is_patchday or $_is_high_prio_patch_day) {
    # Here it is patchday
    if ($_before_patch_window or $_before_prefetch_window or $_before_high_prio_patch_window or $_before_high_prio_prefetch_window) {
      # Before any patching or prefetching, set the runtimeout to the longest duration
      if defined('puppet_agent') {
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
          ini_setting { "puppet-agent-runtimeout":
            ensure  => present,
            section => 'agent',
            setting => 'runtimeout',
            value   => $_longest_duration,
            path    => $puppet_agent::params::config,
          }
        }
      } else {
        # Here the puppet agent_class is not defined elsewhere
        class { 'puppet_agent':
          config => [{ section => 'agent', setting => 'runtimeout', value => $_longest_duration }],
        }
      }
    } elsif ($_after_patch_window or $_after_high_prio_patch_window) {
      # After patching the runtimeout should either be set to what it was previously set to, or back to the default
      if defined('puppet_agent') {
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
          ini_setting { "puppet-agent-runtimeout":
            ensure  => absent,
            section => 'agent',
            setting => 'runtimeout',
            path    => $puppet_agent::params::config,
          }
        }
      } else {
        # Here  the puppet_agent class is not defined
        class { 'puppet_agent':
          config => [{ section => 'agent', setting => 'runtimeout', ensure => absent }],
        }
      }
    }
  } else {
    # Here it is not patchday
    if defined('puppet_agent') {
    } else {
      class { 'puppet_agent':
        config => [{ section => 'main', setting => 'runtimeout', ensure => absent }],
      }
    }
  }

  notify { "info: ${result}": }

  # Determine the available updates if any
  if $facts['pe_patch'] {
    $available_updates = $facts['kernel'] ? {
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
      'Linux' => if $security_only and !$high_priority_only {
        patching_as_code::dedupe_arch($facts['pe_patch']['security_package_updates'])
      } elsif !$high_priority_only {
        patching_as_code::dedupe_arch($facts['pe_patch']['package_updates'])
      } else {
        []
      },
      default => []
    }
    $high_prio_updates = $facts['kernel'] ? {
      'windows' => $facts['pe_patch']['missing_update_kbs'].filter |$item| { $item in $high_priority_list },
      'Linux'   => patching_as_code::dedupe_arch($facts['pe_patch']['package_updates'].filter |$item| { $item in $high_priority_list }),
      default   => []
    }
  }
  else {
    $available_updates = []
    $high_prio_updates = []
  }

  # Determine which updates should get installed if any
  case $allowlist.count {
    0: {
      case $blocklist_mode {
        'strict': {
          $_updates_to_install          = $available_updates.filter |$item| { !($item in $blocklist) }
          $high_prio_updates_to_install = $high_prio_updates.filter |$item| { !($item in $blocklist) }
        }
        'fuzzy': {
          $_updates_to_install          = growell_patch::fuzzy_filter($available_updates, $blocklist)
          $high_prio_updates_to_install = growell_patch::fuzzy_filter($high_prio_updates, $blocklist)
        }
      }
      if ($_is_patchday and $_is_high_prio_patch_day) {
        $updates_to_install = $_updates_to_install.filter |$item| { !($item in $high_prio_updates_to_install) }
      } else {
        $updates_to_install = $_updates_to_install
      }
    }
    default: {
      $whitelisted_updates  = $available_updates.filter |$item| { $item in $allowlist }
      case $blocklist_mode {
        'strict': {
          $_updates_to_install          = $whitelisted_updates.filter |$item| { !($item in $blocklist) }
          $high_prio_updates_to_install = $high_prio_updates.filter |$item| { !($item in $blocklist) }
        }
        'fuzzy': {
          $_updates_to_install          = growell_patch::fuzzy_filter($whitelisted_updates, $blocklist)
          $high_prio_updates_to_install = growell_patch::fuzzy_filter($high_prio_updates, $blocklist)
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
  $_blocklist = $blocklist_mode == 'fuzzy' ? {
    true    => growell_patch::fuzzy_match($available_updates, $blocklist),
    default => $blocklist,
  }

  notify { "available_updates  => ${available_updates}": }
  notify { "high_prio_updates  => ${high_prio_updates}": }
  notify { "updates_to_install => ${updates_to_install}": }
  notify { "_blocklist          => ${_blocklist}": }

  # Determine the states of the pre/post scripts based on operating system
  case $facts['kernel'] {
    'Linux': {
      $_script_base            = '/opt/puppetlabs/pe_patch'
      $_pre_patch_script_path  = "${_script_base}/pre_patch_script.sh"
      $_post_patch_script_path = "${_script_base}/post_patch_script.sh"
      $_pre_reboot_script_path = "${_script_base}/pre_reboot_script.sh"
      $_pre_check_script_path  = "${_script_base}/pre_check_script.sh"
      $_post_check_script_path = "${_script_base}/post_check_script.sh"
      $_fact_file              = 'pe_patch_fact_generation.sh'
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

      # Determine whats needed for pre_patch_script
      if $pre_patch_script == undef {
        $_pre_patch_commands = undef
        $_pre_patch_file_args = {
          ensure => absent,
        }
      } else {
        $_pre_patch_commands = {
          'pre_patch_script' => {
            'command' => $_pre_patch_script_path,
            'path'    => $facts['path'],
          },
        }
        $_pre_patch_file_args = stdlib::merge(
          $_common_present_args,
          { source => "puppet:///modules/${module_name}/${pre_patch_script}" }
        )
      }

      # Determine whats needed for post_patch_script
      if $post_patch_script == undef {
        $_post_patch_commands = undef
        $_post_patch_file_args = {
          ensure => absent,
        }
      } else {
        $_post_patch_commands = {
          'post_patch_script' => {
            'command' => $_post_patch_script_path,
            'path'    => $facts['path'],
          },
        }
        $_post_patch_file_args = stdlib::merge(
          $_common_present_args,
          { source => "puppet:///modules/${module_name}/${post_patch_script}" }
        )
      }

      # Determine whats needed for pre_reboot_script
      if $pre_reboot_script == undef {
        $_pre_reboot_commands = undef
        $_pre_reboot_file_args = {
          ensure => absent,
        }
      } else {
        $_pre_reboot_commands = {
          'pre_reboot_script' => {
            'command' => $_pre_reboot_script_path,
            'path'    => $facts['path'],
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
          exec { 'pre_check_script':
            command => $_pre_check_script_path,
            path    => $facts['path'],
            require => File['pre_check_script'],
            before  => Class['patching_as_code'],
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
        if (($_is_patchday or $_is_high_prio_patch_day) and ($_in_patch_window or $_in_high_prio_patch_window)) {
          exec { 'post_check_script':
            command => $_post_check_script_path,
            path    => $facts['path'],
            require => [File['post_check_script'], Class['patching_as_code']],
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

      unless ($windows_prefetch_before == undef) {
        if ($_in_prefetch_window or $_in_high_prio_prefetch_window) {
          # Need to determine what patches need to be downloaded and passed to Get-WindowsUpdate
          # ex:
          #  Get-WindowsUpdate -KBArticleID "KB5044281" -Download -AcceptAll
          $updates_to_install.each |String $kb| {
            exec { "prefetch ${kb}":
              command  => "Get-WindowsUpdate -KBArticleID ${kb} -Download -AcceptAll",
              provider => 'powershell',
              timeout  => 14400,
            }
          }
        }
      }

      # Determine whats needed for pre_patch_script
      if $pre_patch_script == undef {
        $_pre_patch_commands = undef
        $_pre_patch_file_args = {
          ensure => absent,
        }
      } else {
        $_pre_patch_commands = {
          'pre_patch_script' => {
            'command'  => $_pre_patch_script_path,
            'provider' => 'powershell',
          },
        }
        $_pre_patch_file_args = stdlib::merge(
          $_common_present_args,
          {
            source => "puppet:///modules/${module_name}/${pre_patch_script}"
          }
        )
      }

      # Determine whats needed for post_patch_script
      if $post_patch_script == undef {
        $_post_patch_commands = undef
        $_post_patch_file_args = {
          ensure => absent,
        }
      } else {
        $_post_patch_commands = {
          'post_patch_script' => {
            'command'  => $_post_patch_script_path,
            'provider' => 'powershell',
          },
        }
        $_post_patch_file_args = stdlib::merge(
          $_common_present_args,
          {
            source => "puppet:///modules/${module_name}/${post_patch_script}"
          }
        )
      }

      # Determine whats needed for pre_reboot_script
      if $pre_reboot_script == undef {
        $_pre_reboot_commands = undef
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
          exec { 'pre_check_script':
            command  => $_pre_check_script_path,
            provider => powershell,
            require  => File['pre_check_script'],
            before   => Class['patching_as_code'],
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
        if (($_is_patchday or $_is_high_prio_patch_day) and ($_in_patch_window or $_in_high_prio_patch_window)) {
          exec { 'post_check_script':
            command  => $_post_check_script_path,
            provider => powershell,
            require  => [File['post_check_script'], Class['patching_as_code']],
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
      before  => Class['patching_as_code'],
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

  # Finally we have the information to pass to 'patching_as_code'
  class { 'patching_as_code':
    classify_pe_patch         => true,
    enable_patching           => $enable_patching,
    security_only             => $security_only,
    high_priority_only        => $high_priority_only,
    patch_group               => $patch_group,
    pre_patch_commands        => $_pre_patch_commands,
    post_patch_commands       => $_post_patch_commands,
    pre_reboot_commands       => $_pre_reboot_commands,
    install_options           => $install_options,
    allowlist                 => $allowlist,
    blocklist                 => $_blocklist,
    patch_schedule            => $_patch_schedule,
    high_priority_patch_group => $high_priority_patch_group,
    high_priority_list        => $high_priority_list,
  }
}
