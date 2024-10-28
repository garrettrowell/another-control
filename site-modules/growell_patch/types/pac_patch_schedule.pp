type Growell_patch::Pac_patch_schedule = Struct[
  {
    day_of_week   => Growell_patch::Weekday,
    count_of_week => Integer,
    hours         => String,
    max_runs      => String,
    reboot        => Enum['always', 'never', 'ifneeded'],
  }
]
