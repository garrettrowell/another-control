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
      bool_patch_day     = false
      reboot             = 'never'
      active_pg          = 'never'
      in_patch_window    = false
      in_prefetch_window = false
    elsif patch_group.include? 'always'
      bool_patch_day     = true
      reboot             = 'ifneeded'
      active_pg          = 'always'
      in_patch_window    = true
      in_prefetch_window = true
    else
      patch_group = patch_group.is_a?(String) ? [patch_group] : patch_group
      pg_info = patch_group.map do |pg|
        {
          'name'            => pg,
          'is_patch_day'    => call_function('patching_as_code::is_patchday',
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
        reboot             = patch_schedule[active_pg]['reboot']
        parsed_window      = parse_window(patch_schedule[active_pg]['hours'], time_now)
        in_patch_window    = in_window(parsed_window)
        in_prefetch_window = case windows_prefetch_before.nil?
                             when true
                               false
                             else
                               in_prefetch(windows_prefetch_before, patch_schedule[active_pg]['hours'], time_now)
                             end
      else
        reboot             = 'never'
        in_patch_window    = false
        in_prefetch_window = false
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
        in_high_prio_prefetch_window = case windows_prefetch_before.nil?
                                    when true
                                      false
                                    else
                                      in_prefetch(windows_prefetch_before, patch_schedule[high_priority_patch_group]['hours'], time_now)
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

#    {
#      'is_patch_day'                 => bool_patch_day,
#      'in_patch_window'              => in_patch_window,
#      'reboot'                       => reboot,
#      'active_pg'                    => active_pg,
#      'is_high_prio_patch_day'       => bool_high_prio_patch_day,
#      'in_high_prio_patch_window'    => in_high_prio_patch_window,
#      'high_prio_reboot'             => high_prio_reboot,
#      'in_prefetch_window'           => in_prefetch_window,
#      'in_high_prio_prefetch_window' => in_high_prio_prefetch_window,
#    }
    {
      'normal_patch' => {
        'is_patch_day'    => bool_patch_day,
        'reboot'          => reboot,
        'active_pg'       => active_pg,
        'window'          => {
          'within' => in_patch_window,
          'before' => 'todo',
          'after'  => 'todo',
        },
        'prefetch_window' => {
          'within' => in_prefetch_window,
          'before' => 'todo',
          'after'  => 'todo',
        }
      },
      'high_prio_patch' => {
        'is_patch_day'    => bool_high_prio_patch_day,
        'window'          => {
          'within' => in_high_prio_patch_window,
          'before' => 'todo',
          'after'  => 'todo',
        },
        'prefetch_window' => {
          'within' => in_high_prio_prefetch_window,
          'before' => 'todo',
          'after'  => 'todo',
        }
      }
    }
  end

  # parse a patch schedule and return the start/end time objects
  def parse_window(window, time_now)
    window_arr = window.split('-')
    window_start = window_arr[0].strip
    window_end = window_arr[1].strip
    start_arr = window_start.split(':')
    start_hour = start_arr[0]
    start_min = start_arr[1]
    end_arr = window_end.split(':')
    end_hour = end_arr[0]
    end_min = end_arr[1]
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

  def in_prefetch(prefetch_time, window, time_now)
    prefetch_arr = prefetch_time.split(':')
    prefetch_hour = prefetch_arr[0].to_i * 60 * 60
    prefetch_min = prefetch_arr[1].to_i * 60
    window_arr = window.split('-')
    window_start = window_arr[0].strip
    start_arr = window_start.split(':')
    start_hour = start_arr[0]
    start_min = start_arr[1]
    cur_t = Time.new(time_now.year, time_now.month, time_now.day, time_now.hour, time_now.min)
    start_t = Time.new(time_now.year, time_now.month, time_now.day, start_hour, start_min)
    prefetch_t = (start_t - prefetch_hour) - prefetch_min
    cur_t.between?(prefetch_t, start_t)
  end
end
