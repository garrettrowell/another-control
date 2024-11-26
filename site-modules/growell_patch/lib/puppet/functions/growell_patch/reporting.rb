Puppet::Functions.create_function(:'growell_patch::reporting') do
  dispatch :reporting do
#    param 'Array', :input_arr
#    param 'Array', :filter_arr
  end

  def reporting()
    data = {
      'hello' => 'world'
    }
    vardir = Facter.value('puppet_vardir')
    File.write('/tmp/imatest', 'hello world')
#    File.write("#{vardir}/../../facter/facts.d/growell_patch_report.json", data.to_json)
  end

end
