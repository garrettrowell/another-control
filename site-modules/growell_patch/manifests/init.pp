# @summary A short summary of the purpose of this class
#
# A description of what this class does
#
# @example
#   include growell_patch
class growell_patch (
  Struct[{
    day      => Enum['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
    week     => Integer,
    offset   => Integer,
    hours    => String,
    max_runs => String,
    reboot   => Enum['always', 'never', 'ifneeded'],
  }] $patch_schedule,
  String $patch_group,
) {

  $patchday = growell_patch::patchday($patch_schedule['day'], $patch_schedule['week'], $patch_schedule['offset'])

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
      withpath => false,
      ;
    'patch1':
      message => "Hieradata says we will patch ${patch_schedule['offset']} days after the ${patch_schedule['week']}${week_suffix} ${patch_schedule['day']}",
      ;
    'patch2':
      message => "Which corresponds to the ${patchday['count_of_week']}${patch_suffix} ${patchday['day_of_week']}",
      ;
  }

  class { 'patching_as_code':
    classify_pe_patch => true,
    patch_group       => $patch_group,
    patch_schedule    => {
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
