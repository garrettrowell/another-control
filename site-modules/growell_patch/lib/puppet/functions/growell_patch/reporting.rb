Puppet::Functions.create_function(:'growell_patch::reporting') do
  dispatch :reporting do
    param 'String', :athing
#    param 'Array', :input_arr
#    param 'Array', :filter_arr
  end

  def reporting(athing)
    data = {
      'hello' => athing
    }
    vardir = Facter.value('puppet_vardir')
    File.write('/tmp/imatest', data.to_json)
#    File.write("#{vardir}/../../facter/facts.d/growell_patch_report.json", data.to_json)
  end

end
