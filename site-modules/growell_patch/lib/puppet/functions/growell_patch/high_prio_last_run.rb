Puppet::Functions.create_function(:'growell_patch::high_prio_last_run') do
  dispatch :high_prio_last_run do
    param 'Array', :patches
  end

  def high_prio_last_run(patches)
    {
      'last_run' => Time.now.strftime('%Y-%m-%d %H:%M'),
      'patches_installed' => patches,
    }.to_json
  end
end
