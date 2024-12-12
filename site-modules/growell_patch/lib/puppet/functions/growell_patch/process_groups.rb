Puppet::Functions.create_function(:'growell_patch::process_groups') do
  dispatch :process_groups do
    required_param 'Variant[String[1], Array[String[1]]]',               :patch_group
    required_param 'Hash[String[1], Growell_patch::Pac_patch_schedule]', :patch_schedule
    optional_param 'Optional[String[1]]',                                :high_priority_patch_group
    optional_param 'Optional[String[1]]',                                :windows_prefetch_before
  end

  def process_groups(patch_group, patch_schedule, high_priority_patch_group = nil, windows_prefetch_before = nil)
    # Time object used throughout
    time_now = Time.now
    # Currently only used in debugging
    parsed_window = 0
    # Normal Patch Defaults
    bool_patch_day         = false
    in_patch_window        = false
    in_prefetch_window     = false
    before_patch_window    = false
    after_patch_window     = false
    patch_duration         = 0
    before_prefetch_window = false
    after_prefetch_window  = false
    prefetch_duration      = 0
    # High Priority Patch Defaults
    bool_high_prio_patch_day         = false
    in_high_prio_patch_window        = false
    in_high_prio_prefetch_window     = false
    before_high_prio_patch_window    = false
    after_high_prio_patch_window     = false
    high_prio_patch_duration         = 0
    before_high_prio_prefetch_window = false
    after_high_prio_prefetch_window  = false
    high_prio_prefetch_duration      = 0

    if patch_group.include? 'never'
      active_pg   = 'never'
      post_reboot = 'never'
      pre_reboot  = 'never'
      call_function('create_resources', 'schedule', {
        'growell_patch - Patch Window' => {
          'period' => 'never'
        }
      })
      call_function('create_resources', 'schedule', {
        'growell_patch - Pre Reboot' => {
          'period' => 'never'
        }
      })
    elsif patch_group.include? 'always'
      bool_patch_day  = true
      active_pg       = 'always'
      post_reboot     = 'ifneeded'
      pre_reboot      = 'ifneeded'
      in_patch_window = true
      call_function('create_resources', 'schedule', {
        'growell_patch - Patch Window' => {
          'range'  => '00:00 - 23:59',
          'repeat' => 1440
        }
      })
      call_function('create_resources', 'schedule', {
        'growell_patch - Pre Reboot' => {
          'range'  => '00:00 - 23:59',
          'repeat' => 1
        }
      })
    else
      patch_group = patch_group.is_a?(String) ? [patch_group] : patch_group
      pg_info = patch_group.map do |pg|
        {
          'name'         => pg,
          'is_patch_day' => patchday?(pg, patch_schedule[pg], time_now),
        }
      end
      active_pg = pg_info.reduce(nil) do |memo, value|
        if value['is_patch_day'] == true
          value['name']
        else
          memo
        end
      end
      bool_patch_day = case call_function('type', active_pg, 'generalized')
                       when Puppet::Pops::Types::PStringType
                         true
                       else
                         false
                       end
      if bool_patch_day
        parsed_window       = parse_window(patch_schedule[active_pg], time_now)
        in_patch_window     = parsed_window['current_time'].between?(parsed_window['start_time'], parsed_window['end_time'])
        before_patch_window = parsed_window['current_time'] < parsed_window['start_time']
        after_patch_window  = parsed_window['current_time'] >= parsed_window['end_time']
        patch_duration      = calc_duration(parsed_window['start_time'], parsed_window['end_time'])
        post_reboot         = patch_schedule[active_pg]['post_reboot']
        pre_reboot          = patch_schedule[active_pg]['pre_reboot']
        call_function('create_resources', 'schedule', {
          'growell_patch - Patch Window' => {
            'range'  => patch_schedule[active_pg]['hours'],
            'repeat' => patch_schedule[active_pg]['max_runs']
          }
        })
        call_function('create_resources', 'schedule', {
          'growell_patch - Pre Reboot' => {
            'range'  => patch_schedule[active_pg]['hours'],
            'repeat' => 1
          }
        })
        unless windows_prefetch_before.nil?
          parsed_prefetch        = parse_prefetch(windows_prefetch_before, parsed_window)
          in_prefetch_window     = parsed_window['current_time'].between?(parsed_prefetch, parsed_window['start_time'])
          before_prefetch_window = parsed_window['current_time'] < parsed_prefetch
          after_prefetch_window  = parsed_window['current_time'] >= parsed_window['start_time']
          prefetch_duration      = calc_duration(parsed_prefetch, parsed_window['start_time'])
        end
      else
        post_reboot = 'never'
        pre_reboot  = 'never'
      end
    end

    if high_priority_patch_group == 'never'
      high_prio_post_reboot = 'never'
      high_prio_pre_reboot  = 'never'
      call_function('create_resources', 'schedule', {
        'growell_patch - High Priority Patch Window' => {
          'period' => 'never'
        }
      })
    elsif high_priority_patch_group == 'always'
      bool_high_prio_patch_day  = true
      in_high_prio_patch_window = true
      high_prio_post_reboot     = 'ifneeded'
      high_prio_pre_reboot      = 'ifneeded'
      call_function('create_resources', 'schedule', {
        'growell_patch - High Priority Patch Window' => {
          'range'  => '00:00 - 23:59',
          'repeat' => 1440
        }
      })
    elsif !high_priority_patch_group.nil?
      bool_high_prio_patch_day = patchday?(high_priority_patch_group, patch_schedule[high_priority_patch_group], time_now)

      if bool_high_prio_patch_day
        parsed_high_prio_patch_window = parse_window(patch_schedule[high_priority_patch_group], time_now)
        in_high_prio_patch_window     = parsed_high_prio_patch_window['current_time'].between?(parsed_high_prio_patch_window['start_time'], parsed_high_prio_patch_window['end_time'])
        before_high_prio_patch_window = parsed_high_prio_patch_window['current_time'] < parsed_high_prio_patch_window['start_time']
        after_high_prio_patch_window  = parsed_high_prio_patch_window['current_time'] >= parsed_high_prio_patch_window['end_time']
        high_prio_patch_duration      = calc_duration(parsed_high_prio_patch_window['start_time'], parsed_high_prio_patch_window['end_time'])
        high_prio_post_reboot         = patch_schedule[high_priority_patch_group]['post_reboot']
        high_prio_pre_reboot          = patch_schedule[high_priority_patch_group]['pre_reboot']
        call_function('create_resources', 'schedule', {
          'growell_patch - High Priority Patch Window' => {
            'range'  => patch_schedule[high_priority_patch_group]['hours'],
            'repeat' => patch_schedule[high_priority_patch_group]['max_runs'],
          }
        })

        unless windows_prefetch_before.nil?
          parsed_high_prio_prefetch        = parse_prefetch(windows_prefetch_before, parsed_high_prio_patch_window)
          in_high_prio_prefetch_window     = parsed_high_prio_patch_window['current_time'].between?(parsed_high_prio_prefetch, parsed_high_prio_patch_window['start_time'])
          before_high_prio_prefetch_window = parsed_high_prio_patch_window['current_time'] < parsed_high_prio_prefetch
          after_high_prio_prefetch_window  = parsed_high_prio_patch_window['current_time'] >= parsed_window['start_time']
          high_prio_prefetch_duration      = calc_duration(parsed_high_prio_prefetch, parsed_high_prio_patch_window['start_time'])
        end
      else
        high_prio_post_reboot = 'never'
        high_prio_pre_reboot  = 'never'
      end
    end

    {
      'normal_patch' => {
        'is_patch_day' => bool_patch_day,
        'active_pg'    => active_pg,
        'post_reboot'  => post_reboot,
        'pre_reboot'   => pre_reboot,
        'window'       => {
          'within'   => in_patch_window,
          'before'   => before_patch_window,
          'after'    => after_patch_window,
          'duration' => patch_duration.floor,
        },
        'prefetch_window' => {
          'within'   => in_prefetch_window,
          'before'   => before_prefetch_window,
          'after'    => after_prefetch_window,
          'duration' => prefetch_duration.floor,
        }
      },
      'high_prio_patch' => {
        'is_patch_day' => bool_high_prio_patch_day,
        'post_reboot'  => high_prio_post_reboot,
        'pre_reboot'   => high_prio_pre_reboot,
        'window'       => {
          'within'   => in_high_prio_patch_window,
          'before'   => before_high_prio_patch_window,
          'after'    => after_high_prio_patch_window,
          'duration' => high_prio_patch_duration.floor,
        },
        'prefetch_window' => {
          'within'   => in_high_prio_prefetch_window,
          'before'   => before_high_prio_prefetch_window,
          'after'    => after_high_prio_prefetch_window,
          'duration' => high_prio_prefetch_duration.floor,
        }
      },
      'longest_duration' => [
        patch_duration, prefetch_duration,
        high_prio_patch_duration, high_prio_prefetch_duration
      ].max.floor.to_s,
      'parsed_window'    => parsed_window,
    }
  end

  # parse a patch schedule and return the start/end time objects
  def parse_window(patch_schedule, time_now)
    window_arr   = patch_schedule['hours'].split('-')
    window_start = window_arr[0].strip
    window_end   = window_arr[1].strip
    start_arr    = window_start.split(':')
    start_hour   = start_arr[0]
    start_min    = start_arr[1]
    end_arr      = window_end.split(':')
    end_hour     = end_arr[0]
    end_min      = end_arr[1]
    day_map = {
      'Sunday'    => 0,
      'Monday'    => 1,
      'Tuesday'   => 2,
      'Wednesday' => 3,
      'Thursday'  => 4,
      'Friday'    => 5,
      'Saturday'  => 6
    }
    week_day_to_patch = (day_map[patch_schedule['day_of_week']] - Date.new(time_now.year, time_now.month, 1).wday) % 7 + (patch_schedule['count_of_week'] -1) * 7 + 1
    {
      'start_time'   => Time.new(time_now.year, time_now.month, week_day_to_patch.to_s, start_hour, start_min),
      'end_time'     => Time.new(time_now.year, time_now.month, week_day_to_patch.to_s, end_hour, end_min),
      'current_time' => Time.new(time_now.year, time_now.month, time_now.day, time_now.hour, time_now.min, time_now.sec),
    }
  end

  # parse a prefetch time and return the time object
  def parse_prefetch(prefetch_time, parsed_window)
    prefetch_arr  = prefetch_time.split(':')
    prefetch_hour = prefetch_arr[0].to_i * 60 * 60
    prefetch_min  = prefetch_arr[1].to_i * 60
    (parsed_window['start_time'] - prefetch_hour) - prefetch_min
  end

  # return the number of seconds between two time objects
  def calc_duration(start_time, end_time)
    end_time - start_time
  end

  # determine if it is patchday
  #
  # it is patchday if any of the following are true:
  #   - it is 12hrs before when the patch window starts
  #   - within the patch window
  #   - it is 12hrs after when the patch window ends
  def patchday?(patch_group, patch_schedule, time_now)
    parsed_window = parse_window(patch_schedule, time_now)
    is_before     = parsed_window['current_time'].between?((parsed_window['start_time'] - (60*60*12)), parsed_window['start_time'])
    is_after      = parsed_window['current_time'].between?(parsed_window['end_time'], (parsed_window['end_time'] + (60*60*12)))
    is_between    = parsed_window['current_time'].between?(parsed_window['start_time'], parsed_window['end_time'])
    is_before || is_after  || is_between
  end
end
