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
#
# @example
#   include growell_patch
class growell_patch (
  Hash[String[1], Growell_patch::Patch_schedule] $patch_schedule,
  Variant[String[1], Array[String[1]]] $patch_group,
  Optional[String[1]] $pre_patch_script  = undef,
  Optional[String[1]] $post_patch_script = undef,
  Optional[String[1]] $pre_reboot_script = undef,
  Optional[Array] $install_options = undef,
  Optional[Array] $blocklist = undef,
  Optional[Enum['strict','fuzzy']] $blocklist_mode = undef,
  Optional[String[1]] $pre_check_script = undef,
  Optional[String[1]] $post_check_script = undef,
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

  #$result = growell_patch::process_patch_groups($patch_group, $patch_schedule)
  #  $is_patch_day = 
  #  function patching_as_code::is_patchday(
  #  Enum['Any','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'] $day_of_week,
  #  Variant[Integer, Array] $week_iteration,
  #  String $patch_group
  #)

  # Determine the states of the pre/post scripts based on operating system
  case $facts['kernel'] {
    'Linux': {
      $_script_base            = '/opt/puppetlabs/pe_patch'
      $_pre_patch_script_path  = "${_script_base}/pre_patch_script.sh"
      $_post_patch_script_path = "${_script_base}/post_patch_script.sh"
      $_pre_reboot_script_path = "${_script_base}/pre_reboot_script.sh"
      $_pre_check_script_path  = "${_script_base}/pre_check_script.sh"
      $_post_check_script_path = "${_script_base}/post_check_script.sh"
      $_common_present_args = {
        ensure => present,
        mode   => '0700',
        owner  => 'root',
        group  => 'root',
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
        exec { 'pre_check_script':
          command => $_pre_check_script_path,
          path    => $facts['path'],
          require => File['pre_check_script'],
          before  => Class['patching_as_code'],
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
        exec { 'post_check_script':
          command => $_post_check_script_path,
          path    => $facts['path'],
          require => [File['post_check_script'], Class['patching_as_code']],
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
    classify_pe_patch   => true,
    patch_group         => $patch_group,
    pre_patch_commands  => $_pre_patch_commands,
    post_patch_commands => $_post_patch_commands,
    pre_reboot_commands => $_pre_reboot_commands,
    install_options     => $install_options,
    blocklist           => $blocklist,
    blocklist_mode      => $blocklist_mode,
    patch_schedule      => $_patch_schedule,
  }
}
