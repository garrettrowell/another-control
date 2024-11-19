#!/opt/puppetlabs/puppet/bin/ruby

require_relative "../../ruby_task_helper/files/task_helper.rb"

class MyClass < TaskHelper
  def task(type, reboot, day, week, offset, hours, max_runs, reboot, **kwargs)
    { testing: offset}
#    {greeting: "Hi, my name is #{name}"}
  end
end

if __FILE__ == $0
  MyClass.run
end
