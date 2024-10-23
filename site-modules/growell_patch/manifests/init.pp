# @summary A short summary of the purpose of this class
#
# A description of what this class does
#
# @example
#   include growell_patch
class growell_patch (
  Struct[{
    day      => Growell_patch::Weekday,
    week     => Integer,
    offset   => Integer,
    hours    => String,
    max_runs => String,
    reboot   => Enum['always', 'never', 'ifneeded'],
  }] $patch_schedule,
  String $patch_group,
  Optional[String[1]] $pre_patch_script  = undef,
  Optional[String[1]] $post_patch_script = undef,
  Optional[String[1]] $pre_reboot_script = undef,
) {
  # function determines the patchday to set based on the given day, week and offset
  # for example to achieve: 3 days after the 2nd Thursday.
  $patchday = growell_patch::patchday($patch_schedule['day'], $patch_schedule['week'], $patch_schedule['offset'])

  case $facts['kernel'] {
    'Linux': {
      $_script_base            = '/opt/puppetlabs/pe_patch'
      $_pre_patch_script_path  = "${_script_base}/pre_patch_script.sh"
      $_post_patch_script_path = "${_script_base}/post_patch_script.sh"
      $_pre_reboot_script_path = "${_script_base}/pre_reboot_script.sh"

      $_script_paths = [
        '/usr/local/sbin',
        '/usr/local/bin',
        '/usr/sbin',
        '/usr/bin',
        '/sbin',
        '/bin',
      ]

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
            'path'    => $_script_paths,
          }
        }
        $_pre_patch_file_args = {
          ensure => present,
          source => "puppet:///modules/growell_patch/${pre_patch_script}",
          mode   => '0700',
          owner  => 'root',
          group  => 'root',
        }
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
            'path'    => $_script_paths,
          }
        }
        $_post_patch_file_args = {
          ensure => present,
          source => "puppet:///modules/growell_patch/${post_patch_script}",
          mode   => '0700',
          owner  => 'root',
          group  => 'root',
        }
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
            'path'    => $_script_paths,
          }
        }
        $_pre_reboot_file_args = {
          ensure => present,
          source => "puppet:///modules/growell_patch/${pre_reboot_script}",
          mode   => '0700',
          owner  => 'root',
          group  => 'root',
        }
      }
    }
    'windows': {
      $_script_base            = 'C:/ProgramData/PuppetLabs/pe_patch'
      $_pre_patch_script_path  = "${_script_base}/pre_patch_script.ps1"
      $_post_patch_script_path = "${_script_base}/post_patch_script.ps1"
      $_pre_reboot_script_path = "${_script_base}/pre_reboot_script.ps1"

      # Determine whats needed for pre_patch_script
      if $pre_patch_script == undef {
        $_pre_patch_commands = undef
        $_pre_patch_file_args = {
          ensure => absent
        }
      } else {
        $_pre_patch_commands = {
          'pre_patch_script' => {
            'command'  => $_pre_patch_script_path,
            'provider' => 'powershell',
          }
        }
        $_pre_patch_file_args = {
          ensure => present,
          source => "puppet:///modules/growell_patch/${pre_patch_script}",
          mode   => '0770',
        }
      }

      # Determine whats needed for post_patch_script
      if $post_patch_script == undef {
        $_post_patch_commands = undef
        $_post_patch_file_args = {
          ensure => absent
        }
      } else {
        $_post_patch_commands = {
          'post_patch_script' => {
            'command'  => $_post_patch_script_path,
            'provider' => 'powershell',
          }
        }
        $_post_patch_file_args = {
          ensure => present,
          source => "puppet:///modules/growell_patch/${post_patch_script}",
          mode   => '0770',
        }
      }

      # Determine whats needed for pre_reboot_script
      if $pre_reboot_script == undef {
        $_pre_reboot_commands = undef
        $_pre_reboot_file_args = {
          ensure => absent
        }
      } else {
        $_pre_reboot_commands = {
          'pre_reboot_script' => {
            'command'  => $_pre_reboot_script_path,
            'provider' => 'powershell',
          }
        }
        $_pre_reboot_file_args = {
          ensure => present,
          source => "puppet:///modules/growell_patch/${pre_reboot_script}",
          mode   => '0770',
        }
      }
    }
    default: { fail("Unsupported OS: ${facts['kernel']}") }
  }

  # Manage the various pre/post scripts
  file { 'pre_patch_script':
    path => $_pre_patch_script_path,
    *    => $_pre_patch_file_args,
  }

  file { 'post_patch_script':
    path => $_post_patch_script_path,
    *    => $_post_patch_file_args,
  }

  file { 'pre_reboot_script':
    path => $_pre_reboot_script_path,
    *    => $_pre_reboot_file_args,
  }

  # Helpers only for the notify resources below
  $week_suffix = $patch_schedule['week'] ? {
    1       => 'st',
    2       => 'nd',
    3       => 'rd',
    default => 'th',
  }
  $patch_suffix = $patchday['count_of_week'] ? {
    1       => 'st',
    2       => 'nd',
    3       => 'rd',
    default => 'th',
  }

  # Purely for demonstration purposes
  notify {
    default:
      ;
    'patch1':
      message => "Hieradata says we will patch ${patch_schedule['offset']} days after the ${patch_schedule['week']}${week_suffix} ${patch_schedule['day']}",
      ;
    'patch2':
      message => "Which corresponds to the ${patchday['count_of_week']}${patch_suffix} ${patchday['day_of_week']}",
      ;
  }

  class { 'patching_as_code':
    classify_pe_patch   => true,
    patch_group         => $patch_group,
    pre_patch_commands  => $_pre_patch_commands,
    post_patch_commands => $_post_patch_commands,
    pre_reboot_commands => $_pre_reboot_commands,
    patch_schedule      => {
      $patch_group => {
        day_of_week   => $patchday['day_of_week'],
        count_of_week => $patchday['count_of_week'],
        hours         => $patch_schedule['hours'],
        max_runs      => $patch_schedule['max_runs'],
        reboot        => $patch_schedule['reboot']
      }
    }
  }
}
