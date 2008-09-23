# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.

require 'jtestr'
require 'yaml'

class JtestR::YAMLResultHandler < JtestR::GenericResultHandler

  class << self
    attr_reader :report_file, :data
    attr_accessor :tests

    def report_to(file)
      @report_file = file
      self
    end

    def before
      @data = {}
    end

    def after
      FileUtils.mkdir_p(File.dirname(report_file))
      data[:success] = tests - Array(data[:failure])
      File.open(report_file, 'w') { |f| f.puts YAML::dump(data) }
    end

    def add_failure(test)
      data[:failure] ||= []
      data[:failure] << test unless data[:failure].include? test
    end
  end

  attr_reader :name, :type_name

  def add_fault(fault)
    super
    failure_from_bt = lambda do |ary|
      test = nil
      ary.find do |bt|
        bt = bt.split(':').first.strip
        test = bt if self.class.tests.include?(bt)
      end
      self.class.add_failure(test)
    end
    case fault
    when Test::Unit::Failure
      failure_from_bt.call fault.location
    when Test::Unit::Error, Expectations::Results::Error, Spec::Runner::Reporter::Failure
      failure_from_bt.call fault.exception.backtrace
    when Expectations::Results
      self.class.add_failure(fault.file)
    else
      if fault.respond_to?(:test_header)
        fault.test_header[/\((.+)\)/]
        test = $1.to_s
        self.class.add_failure(test)
      elsif fault.respond_to?(:method)
        test = fault.method.test_class.name
        self.class.add_failure(test)
      end
    end
  end
  
end
