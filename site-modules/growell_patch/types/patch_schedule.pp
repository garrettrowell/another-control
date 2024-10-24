type Growell_patch::Patch_schedule = Struct[{
  day      => Growell_patch::Weekday,
  week     => Integer,
  offset   => Integer,
  hours    => String,
  max_runs => String,
  reboot   => Enum['always', 'never', 'ifneeded'],
}]
