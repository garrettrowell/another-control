class growell_patch::post_check (
  Enum['normal', 'high'] $priority = 'normal',
  Hash $exec_args,
){
  case $priority {
    'normal': {
      $_exec_title = 'post_check_script'
      $_schedule = 'Growell_patch - Patch Window'
      $_notify_title_base = 'Growell_patch - Post Check'
    }
    'high': {
      $_exec_title = 'post_check_script (High Priority)'
      $_schedule = 'Growell_patch - High Priority Patch Window'
      $_notify_title_base = 'Growell_patch - Post Check (High Priority)'
    }
  }

  # Initially record that the post check failed
  notify { "${_notify_title_base} - failed":
    notify   => Exec[$_exec_title],
    schedule => $_schedule,
    message  => Deferred('growell_patch::reporting',
    [
      {
        'post_check' => {
          'status'    => 'failed',
          'timestamp' => Timestamp.new()}}])
  }

  # Run the post check
  exec { $_exec_title:
    schedule => $_schedule,
    *        => $exec_args
  }

  file { '/opt/puppetlabs/growell_patch/reporting.rb':
    ensure  => present,
    mode    => '0700',
    content => epp("${module_name}/reporting.rb.epp"),
  }

  $data = stdlib::to_json({ 'post_check' => { 'status' => 'success', 'timestamp' => Timestamp.new() } })
  # In the event of a failure this resource will get skipped
  exec { "${_notify_title_base} - success":
    command              => "/opt/puppetlabs/growell_patch/reporting.rb -d '${data}'",
    #    command         => "/opt/puppetlabs/puppet/bin/ruby ${epp("${module_name}/reporting.rb.epp",
    #    { 'data'        => {
    #      'post_check'  => {
    #        'status'    => 'success',
    #        'timestamp' => Timestamp.new(),
    #      }}})}",
    refreshonly          => true,
    subscribe            => Exec[$_exec_title],
    schedule             => $_schedule,
  }

  #notify { "${_notify_title_base} - success":
  #  require             => Exec[$_exec_title],
  #  schedule            => $_schedule,
  #  message             => Deferred('growell_patch::reporting',
  #  [
  #    {
  #      'post_check'    => {
  #        'status'      => 'success',
  #        'timestamp'   => Timestamp.new()}}])
  #}

}
