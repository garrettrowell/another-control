Puppet::Functions.create_function(:'adhoc::is_true') do
  dispatch :is_true do
    param 'Boolean', :bool
  end

  def is_true(bool)
    bool
  end
end
