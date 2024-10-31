Puppet::Functions.create_function(:'growell_patch::process_groups') do
  dispatch :process_groups do
    required_param 'Variant[String[1], Array[String[1]]]',               :patch_group
    required_param 'Hash[String[1], Growell_patch::Pac_patch_schedule]', :patch_schedule
    optional_param 'Optional[String[1]]',                                :high_priority_patch_group
    optional_param 'Optional[String[1]]',                                :windows_prefetch_before
  end

  def process_groups(patch_group, patch_schedule, high_priority_patch_group = nil, windows_prefetch_before = nil)
    time_now = Time.now

    if patch_group.include? 'never'
      bool_patch_day         = false
      reboot                 = 'never'
      active_pg              = 'never'
      in_patch_window        = false
      in_prefetch_window     = false
      before_patch_window    = false
      after_patch_window     = false
      patch_duration         = 'n/a'
      before_prefetch_window = false
      after_prefetch_window  = false
      prefetch_duration      = 'n/a'
    elsif patch_group.include? 'always'
      bool_patch_day         = true
      reboot                 = 'ifneeded'
      active_pg              = 'always'
      in_patch_window        = true
      in_prefetch_window     = false
      before_patch_window    = false
      after_patch_window     = false
      patch_duration         = 'n/a'
      before_prefetch_window = false
      after_prefetch_window  = false
      prefetch_duration      = 'n/a'
    else
      patch_group = patch_group.is_a?(String) ? [patch_group] : patch_group
      pg_info = patch_group.map do |pg|
        {
          'name'         => pg,
          'is_patch_day' => call_function('patching_as_code::is_patchday',
                                          patch_schedule[pg]['day_of_week'],
                                          patch_schedule[pg]['count_of_week'],
                                          pg
                                         ),
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
        reboot              = patch_schedule[active_pg]['reboot']
        parsed_window       = parse_window(patch_schedule[active_pg]['hours'], time_now)
        in_patch_window     = in_window(parsed_window)
        before_patch_window = is_before(parsed_window['start_time'], parsed_window['end_time'])
        after_patch_window  = is_after(parsed_window['start_time'], parsed_window['end_time'])
        patch_duration      = calc_duration(parsed_window['start_time'], parsed_window['end_time'])
        if windows_prefetch_before.nil?
          in_prefetch_window     = false
          before_prefetch_window = false
          after_prefetch_window  = false
          prefetch_duration      = 'n/a'
        else
          parsed_prefetch        = parse_prefetch(windows_prefetch_before, parsed_window, time_now)
          in_prefetch_window     = in_prefetch(parsed_prefetch, parsed_window)
          before_prefetch_window = is_before(parsed_prefetch, parsed_window['start_time'])
          after_prefetch_window  = is_after(parsed_prefetch, parsed_window['start_time'])
          prefetch_duration      = calc_duration(parsed_prefetch, parsed_window['start_time'])
        end
      else
        reboot                 = 'never'
        in_patch_window        = false
        in_prefetch_window     = false
        before_patch_window    = false
        after_patch_window     = false
        patch_duration         = 'n/a'
        before_prefetch_window = false
        after_prefetch_window  = false
        prefetch_duration      = 'n/a'
      end
    end

    if high_priority_patch_group == 'never'
      bool_high_prio_patch_day     = false
      in_high_prio_patch_window    = false
      high_prio_reboot             = 'never'
      in_high_prio_prefetch_window = false
    elsif high_priority_patch_group == 'always'
      bool_high_prio_patch_day     = true
      in_high_prio_patch_window    = true
      high_prio_reboot             = 'ifneeded'
      in_high_prio_prefetch_window = true
    elsif high_priority_patch_group != nil
      bool_high_prio_patch_day = call_function('patching_as_code::is_patchday',
                                               patch_schedule[high_priority_patch_group]['day_of_week'],
                                               patch_schedule[high_priority_patch_group]['count_of_week'],
                                               high_priority_patch_group
                                              )
      if bool_high_prio_patch_day
        high_prio_reboot              = patch_schedule[high_priority_patch_group]['reboot']
        parsed_high_prio_patch_window = parse_window(patch_schedule[high_priority_patch_group]['hours'], time_now)
        in_high_prio_patch_window     = in_window(parsed_high_prio_patch_window)
        if windows_prefetch_before.nil?
          in_high_prio_prefetch_window = false
        else
          parsed_high_prio_prefetch    = parse_prefetch(windows_prefetch_before, parsed_high_prio_patch_window, time_now)
          in_high_prio_prefetch_window = in_prefetch(parsed_high_prio_prefetch, parsed_high_prio_patch_window)
        end
      else
        high_prio_reboot             = 'never'
        in_high_prio_patch_window    = false
        in_high_prio_prefetch_window = false
      end
    else
      bool_high_prio_patch_day     = false
      in_high_prio_patch_window    = false
      high_prio_reboot             = 'never'
      in_high_prio_prefetch_window = false
    end

    {
      'normal_patch' => {
        'is_patch_day'    => bool_patch_day,
        'reboot'          => reboot,
        'active_pg'       => active_pg,
        'window'          => {
          'within'   => in_patch_window,
          'before'   => before_patch_window,
          'after'    => after_patch_window,
          'duration' => patch_duration,
        },
        'prefetch_window' => {
          'within'   => in_prefetch_window,
          'before'   => before_prefetch_window,
          'after'    => after_prefetch_window,
          'duration' => prefetch_duration,
        }
      },
      'high_prio_patch' => {
        'is_patch_day'    => bool_high_prio_patch_day,
        'reboot'          => high_prio_reboot,
        'window'          => {
          'within'   => in_high_prio_patch_window,
          'before'   => 'todo',
          'after'    => 'todo',
          'duration' => 'todo',
        },
        'prefetch_window' => {
          'within'   => in_high_prio_prefetch_window,
          'before'   => 'todo',
          'after'    => 'todo',
          'duration' => 'todo',
        }
      }
    }
  end

  # parse a patch schedule and return the start/end time objects
  def parse_window(window, time_now)
    window_arr   = window.split('-')
    window_start = window_arr[0].strip
    window_end   = window_arr[1].strip
    start_arr    = window_start.split(':')
    start_hour   = start_arr[0]
    start_min    = start_arr[1]
    end_arr      = window_end.split(':')
    end_hour     = end_arr[0]
    end_min      = end_arr[1]
    {
      'start_time'   => Time.new(time_now.year, time_now.month, time_now.day, start_hour, start_min),
      'end_time'     => Time.new(time_now.year, time_now.month, time_now.day, end_hour, end_min),
      'current_time' => Time.new(time_now.year, time_now.month, time_now.day, time_now.hour, time_now.min),
    }
  end

  # determine if we are within the provided window
  def in_window(parsed_window)
    parsed_window['current_time'].between?(parsed_window['start_time'], parsed_window['end_time'])
  end

  # parse a prefetch time and return the time object
  def parse_prefetch(prefetch_time, parsed_window, time_now)
    prefetch_arr  = prefetch_time.split(':')
    prefetch_hour = prefetch_arr[0].to_i * 60 * 60
    prefetch_min  = prefetch_arr[1].to_i * 60
    (parsed_window['start_time'] - prefetch_hour) - prefetch_min
  end

  # determine if we are within the provided prefetch window
  def in_prefetch(parsed_prefetch, parsed_window)
    parsed_window['current_time'].between?(parsed_prefetch, parsed_window['start_time'])
  end

  # determine if a given time object occurs before another
  def is_before(start_time, end_time)
    start_time < end_time
  end

  # determine if a given time object occurs after another
  def is_after(start_time, end_time)
    start_time > end_time
  end

  # return the number of seconds between two time objects
  def calc_duration(start_time, end_time)
    end_time - start_time
  end
end
