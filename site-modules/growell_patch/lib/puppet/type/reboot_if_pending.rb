Puppet::Type.newtype(:reboot_if_pending) do
  @doc = 'Perform a clean reboot if it was pending before this agent run'

  newparam(:name) do
    isnamevar
    desc 'Name of this resource (has no function)'
  end

  newparam(:patch_window) do
    desc 'Puppet schedule to link the reboot resource to'
  end

  newparam(:os) do
    desc 'OS type from kernel fact'
  end

  # All parameters are required
  validate do
    [:name, :patch_window, :os].each do |param|
      raise Puppet::Error, "Required parameter missing: #{param}" unless @parameters[param]
    end
  end

  # Add a reboot resource to the catalog if a pending reboot is detected
  def pre_run_check
    # Check for pending reboots
    pending_reboot = false
    kernel = parameter(:os).value.downcase
    case kernel
    when 'windows'
      sysroot = ENV['SystemRoot']
      powershell = "#{sysroot}\\system32\\WindowsPowerShell\\v1.0\\powershell.exe"
      # get the script path relative to the Puppet Type
      checker_script = File.join(
        __dir__,
        '..',
        '..',
        'growell_patch',
        'pending_reboot.ps1',
      )
      pending_reboot = Puppet::Util::Execution.execute("#{powershell} -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -File #{checker_script}", { failonfail: false }).exitstatus.to_i.zero?
    when 'linux'
      # get the script path relative to the Puppet Type
      checker_script = File.join(
        __dir__,
        '..',
        '..',
        'growell_patch',
        'pending_reboot.sh',
      )
      pending_reboot = Puppet::Util::Execution.execute("/bin/sh #{checker_script}", { failonfail: false }).exitstatus.to_i.zero?
    else
      raise Puppet::Error, "Growell_patch - Unsupported Operating System type: #{kernel}"
    end
    return unless pending_reboot

    Puppet.send('notice', 'Growell_patch - Pending OS reboot detected, node will reboot at start of patch window today')
    ## Reorganize dependencies for pre-patch, post-patch and pre-reboot exec resources:
    pre_patch_resources = []
    post_patch_resources = []
    pre_reboot_resources = []
    catalog.resources.each do |res|
      next unless res.type.to_s == 'exec'
      next unless res['tag'].is_a? Array
      next unless (res['tag'] & ['growell_patch_pre_patching', 'growell_patch_post_patching', 'growell_patch_pre_reboot']).any?

      if res['tag'].include?('growell_patch_pre_patching')
        pre_patch_resources << res
      elsif res['tag'].include?('growell_patch_post_patching')
        post_patch_resources << res
      elsif res['tag'].include?('growell_patch_pre_reboot')
        pre_reboot_resources << res
      end
    end
    ## pre-patch resources should gain Reboot[Growell_patch - Pending OS reboot] for require
    pre_patch_resources.each do |res|
      catalog.resource(res.to_s)['require'] = Array(catalog.resource(res.to_s)['require']) << 'Reboot[Growell_patch - Pending OS reboot]'
    end
    ## post-patch resources should lose existing before dependencies
    post_patch_resources.each do |res|
      catalog.resource(res.to_s)['before'] = []
    end
    ## pre-reboot resources should lose existing dependencies
    pre_reboot_resources.each do |res|
      catalog.resource(res.to_s)['require'] = []
      catalog.resource(res.to_s)['before']  = []
    end

    catalog.add_resource(Puppet::Type.type('reboot').new(
                           title: 'Growell_patch - Pending OS reboot',
                           apply: 'immediately',
                           schedule: parameter(:patch_window).value,
                           before: 'Anchor[growell_patch::start]',
                           require: pre_reboot_resources,
                         ))

    catalog.add_resource(Puppet::Type.type('notify').new(
                           title: 'Growell_patch - Performing Pending OS reboot before patching...',
                           message: Deferred('growell_patch::reporting', [{'pre_reboot' => Puppet::Pops::Time::Timestamp.now()}]),
                           schedule: parameter(:patch_window).value,
                           notify: 'Reboot[Growell_patch - Pending OS reboot]',
                           before: 'Anchor[growell_patch::start]',
                           require: pre_reboot_resources,
                         ))
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
