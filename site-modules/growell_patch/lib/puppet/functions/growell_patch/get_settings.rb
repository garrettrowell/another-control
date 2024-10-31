Puppet::Functions.create_function(:'growell_patch::get_settings') do
  dispatch :get_settings do
  end

  def get_settings()
    Puppet.settings[:runtimeout].to_s
  end
end
