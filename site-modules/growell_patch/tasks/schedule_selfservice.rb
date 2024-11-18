#!/usr/bin/env ruby

require_relative "../../ruby_task_helper/files/task_helper.rb"

class MyClass < TaskHelper
  def task(name: nil, **kwargs)
    {greeting: "Hi, my name is #{name}"}
  end
end

if __FILE__ == $0
  MyClass.run
end
