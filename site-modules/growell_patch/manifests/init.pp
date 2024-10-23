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
  Optional[String[1]] $pre_patch_script = undef,
) {
  # function determines the patchday to set based on the given day, week and offset
  # for example to achieve: 3 days after the 2nd Thursday.
  $patchday = growell_patch::patchday($patch_schedule['day'], $patch_schedule['week'], $patch_schedule['offset'])

  # Pre-build the pre-patch command assuming one is set
  $_pre_patch_path = $facts['kernel'] ? {
    'Linux'   => [
      '/usr/local/sbin',
      '/usr/local/bin',
      '/usr/sbin',
      '/usr/bin',
      '/sbin',
      '/bin',
    ],
    'windows' => undef,
  }
  $_pre_patch_provider = $facts['kernel'] ? {
    'Linux'   => undef,
    'windows' => 'powershell',
  }
  $_pre_patch_commands = $pre_patch_script ? {
    undef   => undef,
    default => {
      'prepatch script' => {
        'command'  => epp("growell_patch/${pre_patch_script}"),
        'path'     => $_pre_patch_path,
        'provider' => $_pre_patch_provider,
      }
    }
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
    classify_pe_patch  => true,
    patch_group        => $patch_group,
    pre_patch_commands => $_pre_patch_commands,
    patch_schedule     => {
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
