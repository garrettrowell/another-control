Facter.add('growell_patch_scripts') do
  setcode do
    os = Facter.value('kernel')
    script_base = os == 'windows' ? 'C:/ProgramData/PuppetLabs/pe_patch' : '/opt/puppetlabs/pe_patch'
    script_ext  = os == 'windows' ? '.ps1' : '.sh'
    {
      'post_patch_script' => File.exist?("#{script_base}/post_patch_script#{script_ext}"),
      'pre_patch_script' => File.exist?("#{script_base}/pre_patch_script#{script_ext}")
    }
  end
end
