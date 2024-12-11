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
  Enum['never','always','ifneeded'] $reboot_type = 'never',
  Enum['normal','high'] $priority = 'normal',
  #  Boolean $reboot_if_needed = true,
  Integer $reboot_delay = 60,
  String $report_script_loc,
  Boolean $run_as_plan = false,
  Optional[Timestamp] $super_tuesday_end = undef,
) {
  $reboot_delay_min = round($reboot_delay / 60)
  case $priority {
    'normal': {
      $_reboot_title = 'Growell_patch - Pre Patch Reboot'
      $_schedule = $run_as_plan ?{
        false => 'Growell_patch - Patch Window',
        true  => undef,
      }
      $_notify_title = 'Growell_patch - Performing Pre Patch OS reboot'
      $_reboot_if_pending_title = 'Growell_patch - Pre'
    }
    'high': {
      $_reboot_title = 'Growell_patch - High Priority Pre Patch Reboot'
      $_schedule = $run_as_plan ? {
        false => 'Growell_patch - High Priority Patch Window',
        true  => undef,
      }
      $_notify_title = 'Growell_patch - Performing High Priority Pre Patch OS reboot'
      $_reboot_if_pending_title = 'Growell_patch High Priority - Pre'
    }
  }

  if $run_as_plan {
    $_needs_reboot = true
  } else {
    if $facts['growell_patch_report'].dig('pre_reboot') {
      # check if pre_reboot timestamp is for this month
      $cur = growell_patch::within_cur_month($facts['growell_patch_report']['pre_reboot'])
      if $cur {
        if $super_tuesday_end > Timestamp($facts['growell_patch_report']['pre_reboot']) {
          $_needs_reboot = true
        } else {
          $_needs_reboot = false
        }
        # check if we're greater than the timestamp
        #$_needs_reboot = Timestamp.new() < Timestamp($facts['growell_patch_report']['pre_reboot'])
      } else {
        $_needs_reboot = true
      }
    } else {
      # if the pre_reboot key is not in our report we should reboot assuming its pending
      $_needs_reboot = true
    }
  }

  case $reboot_type {
    'never': {
    }
    'always': {
      if $_needs_reboot {
        # Reboot as part of this Puppet run
        reboot { $_reboot_title:
          apply    => 'immediately',
          schedule => $_schedule,
          timeout  => $reboot_delay,
        } -> Exec <| tag == "${module_name}_pre_check" |>
        # Record the pre_reboot timestamp
        $data = stdlib::to_json(
          {
            'pre_reboot' => Timestamp.new(),
          }
        )
        exec { $_notify_title:
          command  => "${report_script_loc} -d '${data}'",
          notify   => Reboot[$_reboot_title],
          schedule => $_schedule,
        }
      }
    }
    'ifneeded': {
      # Define an Exec to perform the reboot shortly after the Puppet run completes
      case $facts['kernel'].downcase() {
        'windows': {
          $reboot_logic_provider = 'powershell'
          $reboot_logic_cmd      = "& shutdown /r /t ${reboot_delay} /c \"Growell_patch: Rebooting system due to a pending reboot before patching\" /d p:2:17" # lint:ignore:140chars 
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
      if $_needs_reboot {
        reboot_if_pending { $_reboot_if_pending_title:
          patch_window => $_schedule,
          os           => $facts['kernel'].downcase,
        } -> Exec <| tag == "${module_name}_pre_check" |>

        # Record the pre_reboot timestamp
        $data = stdlib::to_json(
          {
            'pre_reboot' => Timestamp.new(),
          }
        )
        exec { $_notify_title:
          command  => "${report_script_loc} -d '${data}'",
          notify   => Reboot_if_pending[$_reboot_if_pending_title],
          schedule => $_schedule,
        }
      }
    }
  }
}
