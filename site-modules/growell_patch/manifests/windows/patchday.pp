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
        ensure      => 'present',
        maintwindow => 'Growell_patch - Patch Window',
      }
    }
  }

  if $high_prio_updates.count > 0 {
    $high_prio_updates.each | $kb | {
      growell_patch::kb { $kb:
        ensure      => 'present',
        maintwindow => 'Growell_patch - High Priority Patch Window',
      }
    }
  }

  anchor { 'growell_patch::patchday::end': } #lint:ignore:anchor_resource
}
