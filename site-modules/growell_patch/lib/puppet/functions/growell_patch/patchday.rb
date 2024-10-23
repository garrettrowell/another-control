Puppet::Functions.create_function(:'growell_patch::patchday') do
  dispatch :patchday do
    required_param "Enum['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']", :day
    required_param 'Integer', :week
    required_param 'Integer', :offset
  end

  def patchday(day, week, offset)
    cond = condition_date(day, week)
    outdate = desired_date(cond, offset)
    {
      'day_of_week'   => get_day(outdate),
      'count_of_week' => nth_occurance(outdate)
    }
  end

  DAYS_MAPPING = {
    0=>"Sunday",
    1=>"Monday",
    2=>"Tuesday",
    3=>"Wednesday",
    4=>"Thursday",
    5=>"Friday",
    6=>"Saturday"
  }

  def get_day(date)
    DAYS_MAPPING[date.wday]
  end

  def new_by_mday(year, month, weekday, nr)
    raise( ArgumentError, "No number for weekday/nr") unless weekday.respond_to?(:between?) and nr.respond_to?(:between?)
    raise( ArgumentError, "Number not in Range 1..5: #{nr}") unless nr.between?(1,5)
    raise( ArgumentError,  "Weekday not between 0 (Sunday)and 6 (Saturday): #{nr}") unless weekday.between?(0,6)

    day =  (weekday-Date.new(year, month, 1).wday)%7 + (nr-1)*7 + 1

    if nr == 5
      lastday = (Date.new(year, (month)%12+1, 1)-1).day # each december has the same no. of days
      raise "There are not 5 weekdays with number #{weekday} in month #{month}" if day > lastday
    end

    Date.new(year, month, day)
  end

  # for example return the second Tuesday of the current month/year
  #   condition_date('Tuesday', 2)
  def condition_date(day, nth)
    today = Date.today
    new_by_mday(today.year, today.month, Date.parse(day).wday, nth)
  end

  # date of the weekday after the conditional
  def desired_date(conditional_date, offset)
    # int representing the conditional_date's day
    conditional_date + offset
  end

  def nth_occurance(date)
    (date.mday.to_f / 7).ceil
  end
end

