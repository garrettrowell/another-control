# Class: patching_as_code::reboot
#
# @summary
#   This class gets called by init.pp to reboot the node. You can use Hiera to set a different default for the reboot_delay if desired.
# @param [Boolean] reboot_if_needed
#   Only reboot the node if a system reboot is pending. This parameter is passed automatically from init.pp
# @param [Integer] reboot_delay
#   Time in seconds to delay the reboot by, defaults to 2 minutes.
#   To override for patching, specify an alternate value by setting the patching_as_code::reboot::reboot_delay parameter in Hiera.
class growell_patch::reboot (
  Boolean $reboot_if_needed = true,
  Integer $reboot_delay = 120,
  String $report_script_loc,
) {
  $reboot_delay_min = round($reboot_delay / 60)
  if $reboot_if_needed {
    # Define an Exec to perform the reboot shortly after the Puppet run completes
    case $facts['kernel'].downcase() {
      'windows': {
        $reboot_logic_provider = 'powershell'
        $reboot_logic_cmd      = "& shutdown /r /t ${reboot_delay} /c \"Growell_patch: Rebooting system due to a pending reboot after patching\" /d p:2:17" # lint:ignore:140chars 
        $reboot_logic_onlyif   = "${facts['puppet_vardir']}/lib/${module_name}/pending_reboot.ps1"
      }
      'linux': {
        $reboot_logic_provider = 'posix'
        $reboot_logic_cmd      = "/sbin/shutdown -r +${reboot_delay_min}"
        $reboot_logic_onlyif   = "/bin/sh ${facts['puppet_vardir']}/lib/${module_name}/pending_reboot.sh"
      }
      default: {
        fail('Unsupported operating system for Growell_patch!')
      }
    }
    exec { 'Growell_patch - Patch Reboot':
      command   => $reboot_logic_cmd,
      onlyif    => $reboot_logic_onlyif,
      provider  => $reboot_logic_provider,
      logoutput => true,
      schedule  => 'Growell_patch - Patch Window',
    }

    $data = stdlib::to_json(
      {
        'post_reboot' => Timestamp.new(),
      }
    )
    exec { 'Growell_patch - Performing OS reboot':
      command  => "${report_script_loc} -d '${data}'",
      notify   => Exec['Growell_patch - Patch Reboot'],
      schedule => 'Growell_patch - Patch Window',
    }

  } else {
    # Reboot as part of this Puppet run
    reboot { 'Growell_patch - Patch Reboot':
      apply    => 'immediately',
      schedule => 'Growell_patch - Patch Window',
      timeout  => $reboot_delay,
    }

    $data = stdlib::to_json(
      {
        'post_reboot' => Timestamp.new(),
      }
    )
    exec { 'Growell_patch - Performing OS reboot':
      command  => "${report_script_loc} -d '${data}'",
      notify   => Reboot['Growell_patch - Patch Reboot'],
      schedule => 'Growell_patch - Patch Window',
    }

    #notify { 'Growell_patch - Performing OS reboot':
    #  notify   => Reboot['Growell_patch - Patch Reboot'],
    #  schedule => 'Growell_patch - Patch Window',
    #}
  }
}

