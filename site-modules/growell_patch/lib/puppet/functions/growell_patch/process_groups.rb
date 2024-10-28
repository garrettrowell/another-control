Puppet::Functions.create_function(:'growell_patch::process_groups') do
  dispatch :process_groups do
    required_param 'Variant[String[1], Array[String[1]]]', :patch_group
    required_param 'Hash[String[1], Hash]',                :patch_schedule
    optional_param 'Optional[String[1]]',                  :high_priority_patch_group
  end

  def process_groups(patch_group, patch_schedule, high_priority_patch_group = nil)
    if patch_group.include? 'never'
      bool_patch_day = false
      reboot         = 'never'
      active_pg      = 'never'
    elsif patch_group.include? 'always'
      bool_patch_day = true
      reboot         = 'ifneeded'
      active_pg      = 'always'
    else
      pg_info = patch_group.map do |pg|
        {
          'name' => pg,
          'is_patch_day' => call_function('patching_as_code::is_patchday',
                                          patch_schedule[pg]['day_of_week'],
                                          patch_schedule[pg]['count_of_week'],
                                          pg
                                         )
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
        reboot = patch_schedule[active_pg]['reboot']
      else
        reboot = 'never'
      end
    end

    if high_priority_patch_group == 'never'
      bool_high_prio_patch_day = false
      high_prio_reboot         = 'never'
    elsif high_priority_patch_group == 'always'
      bool_high_prio_patch_day = true
      high_prio_reboot         = 'ifneeded'
    elsif high_priority_patch_group != nil
      bool_high_prio_patch_day = call_function('patching_as_code::is_patchday',
                                               patch_schedule[high_priority_patch_group]['day_of_week'],
                                               patch_schedule[high_priority_patch_group]['count_of_week'],
                                               high_priority_patch_group
                                              )
      if bool_high_prio_patch_day
        high_prio_reboot = patch_schedule[high_priority_patch_group]['reboot']
      else
        high_prio_reboot = 'never'
      end
    else
      bool_high_prio_patch_day = false
      high_prio_reboot         = 'never'
    end

    {
      'is_patch_day'           => bool_patch_day,
      'reboot'                 => reboot,
      'active_pg'              => active_pg,
      'is_high_prio_patch_day' => bool_high_prio_patch_day,
      'high_prio_reboot'       => high_prio_reboot
    }
  end

end
