# Class: patching_as_code::windows::patchday
# 
# @summary
#   This class gets called by init.pp to perform the actual patching on Windows.
# @param [Array] updates
#   List of Windows KB patches to install.
# @param [Array] high_prio_updates
#   List of high-priority Windows KB patches to install.
class growell_patch::windows::patchday (
  Array $updates,
  Array $high_prio_updates = [],
  Array $install_options = [],
  String $report_script_loc,
) {
  if $updates.count > 0 {
    $updates.each | $kb | {
      growell_patch::kb { $kb:
        ensure            => 'present',
        maintwindow       => "${module_name} - Patch Window",
        report_script_loc => $report_script_loc,
      }
    }
  }

  if $high_prio_updates.count > 0 {
    $high_prio_updates.each | $kb | {
      growell_patch::kb { $kb:
        ensure            => 'present',
        maintwindow       => "${module_name} - High Priority Patch Window",
        report_script_loc => $report_script_loc,
      }
    }
  }

  anchor { "${module_name}::patchday::end": } #lint:ignore:anchor_resource
}
