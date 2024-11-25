Puppet::Type.newtype(:patch_package) do
  @doc = 'Define a package resource to patch'

  newparam(:name) do
    isnamevar
    desc 'Name of the package to patch'
  end

  newparam(:patch_window) do
    desc 'Puppet schedule to link package resource to'
  end

  newparam(:install_options) do
    desc 'Array of install options to optionally pass'
  end

  # All parameters are required
  validate do
    [:name, :patch_window].each do |param|
      raise Puppet::Error, "Required parameter missing: #{param}" unless @parameters[param]
    end
  end

  # See if the package to patch exists in the catalog
  # If package is not found, create a one-time package resource
  def eval_generate
    package_in_catalog = if retrieve_package_title(name).empty?
                           false
                         else
                           true
                         end

    if package_in_catalog
      []
    else
      [Puppet::Type.type(:package).new(name: name,
                                        ensure: 'latest',
                                        schedule: self[:patch_window],
                                        install_options: self[:install_options],
                                        before: 'Anchor[growell_patch::patchday::end]')]
    end
  end

  # See if the package to patch exists in the catalog
  # If package is found, update resource one-time for patching
  def pre_run_check
    package_res = retrieve_package_title(name)
    if package_res.empty?
      package_in_catalog = false
    else
      res = retrieve_resource_reference(package_res)
      package_in_catalog = true
    end

    if package_in_catalog
      if ['present', 'installed', 'latest'].include?(res['ensure'].to_s)
        Puppet.send('notice', "Package[#{name}] (managed) will be updated by Growell_patch")
        catalog.resource(package_res)['ensure'] = 'latest'
        catalog.resource(package_res)['schedule'] = self[:patch_window]
        catalog.resource(package_res)['install_options'] = self[:install_options]
        catalog.resource(package_res)['before'] = Array(res['before']) + ['Anchor[growell_patch::patchday::end]']
        catalog.resource(package_res)['require'] = (Array(res['require']) + ['Exec[Growell_patch - Clean Cache]'])
      else
        Puppet.send('notice', "Package[#{name}] (managed) will not be updated by Growell_patch, due to the package enforcing a specific version")
      end
    else
      Puppet.send('notice', "Package[#{name}] (unmanaged) will be updated by Growell_patch")
    end
  end

  def retrieve_package_title(package)
    title = ''
    catalog.resources.each do |res|
      next unless res.type.to_s == 'package'

      if res['name'] == package
        title = "Package[#{res.title}]"
        break
      end
    end
    title
  end

  def retrieve_resource_reference(res)
    case res
    when Puppet::Type
    when Puppet::Resource
    when String
      begin
        Puppet::Resource.new(res)
      rescue ArgumentError
        raise ArgumentError, "#{res} is not a valid resource reference"
      end
    else
      raise ArgumentError, "#{res} is not a valid resource reference"
    end

    resource = catalog.resource(res.to_s)

    raise ArgumentError, "#{res} is not in the catalog" unless resource

    resource
  end
end

