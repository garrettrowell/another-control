Puppet::Functions.create_function(:'growell_patch::reporting') do
  dispatch :reporting do
    param 'Hash', :data
  end

  def reporting(data)
    vardir = Facter.value(:puppet_vardir)
#    File.write('/tmp/imatest', data.to_json)
    report = Facter.value(:growell_patch_report)
    if report
      _data = report.merge(data)
    else
      _data = data
    end
    File.write("#{vardir}/../../facter/facts.d/growell_patch_report.json", _data.to_json)
  end

end
