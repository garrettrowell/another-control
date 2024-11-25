Puppet::Functions.create_function(:'growell_patch::last_run') do
  dispatch :last_run do
    param 'Array', :patches
  end

  def last_run(patches, choco_patches)
    {
      'last_run' => Time.now.strftime('%Y-%m-%d %H:%M'),
      'patches_installed' => patches,
    }.to_json
  end
end
