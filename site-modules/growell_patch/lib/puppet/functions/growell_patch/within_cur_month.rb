Puppet::Functions.create_function(:'growell_patch::within_cur_month') do
  dispatch :within_cur_month do
    required_param 'String', :timestamp
  end

  def within_cur_month(timestamp)
    today = Date.today
    first = Date.new(today.year, today.month, 1)
    last  = Date.new(today.year, today.month, -1)
    Date.parse(timestamp).between?(first, last)
  end
end
