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

require 'yaml'

module Buildr #:nodoc:
  module TestFramework
    
    # A class used by buildr for jruby based frameworks, so that buildr can know 
    # which tests succeeded/failed.
    class TestResult

      class Error < ::Exception
        attr_reader :message, :backtrace
        def initialize(message, backtrace)
          @message = message
          @backtrace = backtrace
        end
      end
      
      class << self
        def for_rspec
          unless const_defined?(:RSpec)
            require 'spec/runner/formatter/base_formatter' # lazy loading only when using Rspec
            cls = Class.new(Spec::Runner::Formatter::BaseFormatter) { include YamlFormatter }
            const_set :RSpec, cls
          end
        end
      
        def for_jtestr
          unless const_defined?(:JtestR)
            for_rspec
            require 'jtestr' # lazy loading only when using JtestR
            cls = Class.new { include RSpecResultHandler }
            const_set :JtestR, cls
          end
        end
      end

      attr_accessor :failed, :succeeded

      def initialize
        @failed, @succeeded = [], []
      end

      module YamlFormatter
        attr_reader :result
        
        def start(example_count)
          super
          @result = TestResult.new
        end

        def close
          files = options.files
          failure_from_bt = lambda do |ary|
            test = nil
            ary.find do |bt|
              bt = bt.split(':').first.strip
              test = bt if files.include?(bt)
            end
            test
          end
          options.reporter.instance_variable_get(:@failures).each do |failure|
            result.failed << files.delete(failure_from_bt[failure.exception.backtrace])
          end
          result.succeeded |= files
          
          FileUtils.mkdir_p(File.dirname(where))
          File.open(where, 'w') { |f| f.puts YAML.dump(result) }
        end
      end # YamlFormatter

      
      # A JtestR ResultHandler
      # Using this handler we can use RSpec formatters, like html/ci_reporter with JtestR
      # Created for YamlFormatter
      module RSpecResultHandler
        def self.included(mod)
          mod.extend ClassMethods
          super
        end

        module ClassMethods
          # an rspec reporter used to proxy events to rspec formatters
          attr_reader :reporter

          def options=(options)
            @reporter = Spec::Runner::Reporter.new(options)            
          end

          def before
            reporter.start(reporter.options.files.size)
          end

          def after
            reporter.end
            reporter.dump
          end
        end

        module ExampleMethods
          attr_accessor :name, :description, :__full_description
        end

        def reporter
          self.class.reporter
        end

        attr_accessor :example_group, :current_example, :current_failure

        def initialize(name, desc, *args)
          self.example_group = ::Spec::Example::ExampleGroup.new(desc)
          reporter.add_example_group(example_group)
        end

        def starting
        end

        def ending
        end

        def add_fault(fault)
          self.current_failure = fault
        end

        def add_pending(pending)
        end

        def starting_single(name = nil)
          self.current_failure = nil
          self.current_example = Object.new
          current_example.extend ::Spec::Example::ExampleMethods
          current_example.extend ExampleMethods
          desc = name.to_s[/(.*)\(/] ? $1 : name.to_s
          current_example.description = desc
          current_example.__full_description = "#{example_group.description} #{desc}"
          reporter.example_started(current_example)
        end

        def succeed_single(name = nil)
          fail_unless_current(name)
          reporter.example_finished(current_example)
        end

        def fail_single(name = nil)
          fail_unless_current(name)
          reporter.failure(current_example, current_error)
        end

        def error_single(name = nil)
          fail_unless_current(name)
          reporter.example_finished(current_example, current_error)
        end

        def pending_single(name = nil)
          fail_unless_current(name)
          error = ::Spec::Example::ExamplePendingError.new(name)
          reporter.example_finished(current_example, error)
        end

      private
        def fail_unless_current(name)
          fail "Expected #{name.inspect} to be current example but was #{current_example.description}" unless current_example.description == name.to_s
        end

        def current_error
          fault = current_failure
          case fault
          when nil
            nil
          when Test::Unit::Failure
            Error.new(fault.message, fault.location)
          when Test::Unit::Error, Expectations::Results::Error, Spec::Runner::Reporter::Failure
            fault.exception
          when Expectations::Results
            fault
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

        
      end # RSpecResultHandler
      
    end # TestResult
  end
end
