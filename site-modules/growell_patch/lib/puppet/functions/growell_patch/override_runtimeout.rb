Puppet::Functions.create_function(:'growell_patch::override_runtimeout') do
  dispatch :override_runtimeout do
  end

  def override_runtimeout()
    Puppet.settings[:runtimeout] = 14400
  end
end
