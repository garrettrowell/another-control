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
  String $patch_group
) {

  $test = growell_patch::patchday($patch_schedule['day'], $patch_schedule['week'], $patch_schedule['offset'])
  notify { "patchday: ${test}": }

  class { 'patching_as_code':
    classify_pe_patch => true,
    patch_group       => $patch_group,
    patch_schedule    => {
      $patch_group => {
        day_of_week   => $test['day_of_week'],
        count_of_week => $test['count_of_week'],
        hours         => $patch_schedule['hours'],
        max_runs      => $patch_schedule['max_runs'],
        reboot        => $patch_schedule['reboot']
      }
    }
  }
}

# @param [Hash] patch_schedule
#   Hash of available patch_schedules. Default schedules are in /data/common.yaml of this module
# @option patch_schedule [String] :day_of_week
#   Day of the week to patch, valid options: 'Any', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
# @option patch_schedule [Variant[Integer,Array[Integer]]] :count_of_week
#   Which week(s) in the month to patch, use number(s) between 1 and 5
#
# @option patch_schedule [String] :hours
#   Which hours on patch day to patch, define a range as 'HH:MM - HH:MM'
# @option patch_schedule [String] :max_runs
#   How many Puppet runs during the patch window can Puppet install patches. Must be at least 1.
# @option patch_schedule [String] :reboot
#   Reboot behavior, valid options: 'always', 'never', 'ifneeded'
