# Class: patching_as_code::linux::patchday
# 
# @summary
#   This class gets called by init.pp to perform the actual patching on Linux.
# @param [Array] updates
#   List of Linux packages to update.
# @param [Array] high_prio_updates
#   List of high-priority Linux packages to update.
class growell_patch::linux::patchday (
  Array $updates,
  Array $high_prio_updates = [],
  Array $install_options = [],
  String $report_script_loc,
) {
  case $facts['package_provider'] {
    'yum': {
      $cmd      = 'yum clean all'
      $cmd_path = '/usr/bin'
    }
    'dnf': {
      $cmd      = 'dnf clean all'
      $cmd_path = '/usr/bin'
    }
    'apt': {
      $cmd      = 'apt-get clean'
      $cmd_path = '/usr/bin'
    }
    'zypper': {
      $cmd      = 'zypper cc --all'
      $cmd_path = '/usr/bin'
    }
    default: {
      $cmd = 'true'
      $cmd_path = '/usr/bin'
    }
  }

  if $updates.count > 0 {
    exec { "${module_name} - Clean Cache":
      command  => $cmd,
      path     => $cmd_path,
      schedule => "${module_name} - Patch Window",
    }

    $updates.each | $package | {
      patch_package { $package:
        patch_window    => "${module_name} - Patch Window",
        install_options => $install_options,
        require         => Exec["${module_name} - Clean Cache"],
      }

      $install_data = stdlib::to_json(
        {
          'updates_installed' => {
            'timestamp' => Timestamp.new(),
            'packages'  => {
              $package    => Timestamp.new(),
            }
          }
        }
      )

      exec { "${package} - Installed":
        command     => "${report_script_loc} -d '${install_data}'",
        subscribe   => Patch_package[$package],
        refreshonly => true,
        schedule    => "${module_name} - Patch Window",
      }
    }
  }

  if $high_prio_updates.count > 0 {
    exec { "${module_name} - Clean Cache (High Priority)":
      command  => $cmd,
      path     => $cmd_path,
      schedule => "${module_name} - High Priority Patch Window",
    }

    $high_prio_updates.each | $package | {
      patch_package { $package:
        patch_window    => "${module_name} - High Priority Patch Window",
        install_options => $install_options,
        require         => Exec["${module_name} - Clean Cache (High Priority)"],
      }

      $install_data = stdlib::to_json(
        {
          'updates_installed' => {
            'timestamp' => Timestamp.new(),
            'packages'  => {
              $package    => Timestamp.new(),
            }
          }
        }
      )

      exec { "${package} - Installed (High Priority)":
        command     => "${report_script_loc} -d '${install_data}'",
        subscribe   => Patch_package[$package],
        refreshonly => true,
        schedule    => "${module_name} - High Priority Patch Window",
      }

    }
  }

  anchor { "${module_name}::patchday::end": } #lint:ignore:anchor_resource
}
