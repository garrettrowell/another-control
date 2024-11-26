Puppet::Functions.create_function(:'growell_patch::reporting') do
  dispatch :reporting do
#    param 'Array', :input_arr
#    param 'Array', :filter_arr
  end

  def reporting()
    data = {
      'hello' => 'world'
    }
    File.write("#{vardir_fact}/../../facter/facts.d/growell_patch_report.json", data.to_json)
  end

  def vardir_fact
    closure_scope['facts']['puppet_vardir']
  end
end
