# Class: patching_as_code::reboot
#
# @summary
#   This class gets called by init.pp to reboot the node. You can use Hiera to set a different default for the reboot_delay if desired.
# @param [Boolean] reboot_if_needed
#   Only reboot the node if a system reboot is pending. This parameter is passed automatically from init.pp
# @param [Integer] reboot_delay
#   Time in seconds to delay the reboot by, defaults to 1 minutes.
#   To override for patching, specify an alternate value by setting the patching_as_code::reboot::reboot_delay parameter in Hiera.
class growell_patch::pre_reboot (
  String $reboot_type = 'never',
  #  Boolean $reboot_if_needed = true,
  Integer $reboot_delay = 60
) {
  $reboot_delay_min = round($reboot_delay / 60)
  case $reboot_type {
    'never': {
    }
    'always': {
      if $facts['growell_patch_report'].dig('pre_reboot') {
        # check if pre_reboot timestamp is for this month
        $cur = growell_patch::within_cur_month($facts['growell_patch_report']['pre_reboot'])
        if $cur {
          # check if we're greater than the timestamp
          $_needs_reboot = Timestamp.new() < Timestamp($facts['growell_patch_report']['pre_reboot'])
        } else {
          $_needs_reboot = true
        }
      } else {
        # if the pre_reboot key is not in our report we must always reboot once
        $_needs_reboot = true
      }
      if $_needs_reboot {
        # Reboot as part of this Puppet run
        reboot { 'Growell_patch - Pre Patch Reboot':
          apply    => 'immediately',
          schedule => 'Growell_patch - Patch Window',
          timeout  => $reboot_delay,
        }
        notify { 'Growell_patch - Performing Pre Patch OS reboot':
          notify   => Reboot['Growell_patch - Pre Patch Reboot'],
          schedule => 'Growell_patch - Patch Window',
          message  => Deferred('growell_patch::reporting', [{'pre_reboot' => Timestamp.new()}])
        }
      }
    }
    'ifneeded': {
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
      if $facts['growell_patch_report'].dig('pre_reboot') {
        # check if pre_reboot timestamp is for this month
        $cur = growell_patch::within_cur_month($facts['growell_patch_report']['pre_reboot'])
        if $cur {
          # check if we're greater than the timestamp
          $_needs_reboot = Timestamp.new() < Timestamp($facts['growell_patch_report']['pre_reboot'])
        } else {
          $_needs_reboot = true
        }
      } else {
        # if the pre_reboot key is not in our report we should reboot assuming its pending
        $_needs_reboot = true
      }
      if $_needs_reboot {
        reboot_if_pending { 'Growell_patch':
          patch_window => 'Growell_patch - Patch Window',
          os           => $facts['kernel'].downcase,
        }
        #exec { 'Growell_patch - Pre Patch Reboot':
        #  command   => $reboot_logic_cmd,
        #  onlyif    => $reboot_logic_onlyif,
        #  provider  => $reboot_logic_provider,
        #  logoutput => true,
        #  schedule  => 'Growell_patch - Patch Window',
        #}
        #notify { 'Growell_patch - Performing Pre Patch OS reboot ifneeded':
        #  notify   => Exec['Growell_patch - Pre Patch Reboot'],
        #  schedule => 'Growell_patch - Patch Window',
        #  message  => Deferred('growell_patch::reporting', [{'pre_reboot' => Timestamp.new()}])
        #}
      }
    }
  }
}
