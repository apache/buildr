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

# necessary to require YAML even if it is mentioned by autoload as it fails on some platforms.
require 'yaml' 
require 'fileutils'
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
          set_backtrace backtrace
        end

        def self.dump_yaml(file, e)
          FileUtils.mkdir_p File.dirname(file)
          File.open(file, 'w') { |f| f.puts(YAML.dump(Error.new(e.message, e.backtrace))) }
        end

        def self.guard(file)
          begin
            yield
          rescue => e
            dump_yaml(file, e)
          end
        end
      end

      attr_accessor :failed, :succeeded

      def initialize
        @failed, @succeeded = [], []
      end

      # An Rspec formatter used by buildr
      class YamlFormatter
        attr_reader :result

        attr_accessor :example_group, :options, :where

        def initialize(options, where)
          @options = options
          @where = where
          @result = Hash.new
          @result[:succeeded] = []
          @result[:failed] = []
        end

        %w[ example_started
            start_dump dump_failure dump_summary dump_pending ].each do |meth|
          module_eval "def #{meth}(*args); end"
        end

        def example_group_started(example_group)
          @example_group = example_group
        end

        def example_passed(example)
          result.succeeded << example_name(example)
        end

        def example_pending(example, counter)
          result.succeeded << example_name(example)
        end

        def example_failed(example, counter, failure)
          result.failed << example_name(example)
        end

        def start(example_count)
          @result = TestResult.new
        end

        def close
          result.succeeded = result.succeeded - result.failed
          FileUtils.mkdir_p File.dirname(where)
          File.open(where, 'w') { |f| f.puts YAML.dump(result) }
        end

      private
        def example_name(example)
          if Spec::Example::ExampleProxy === example
            example_group.location.gsub(/:\d+$/, '')
          else
            example.name.gsub(/(.+)(\..+\(\))/, '\1')
          end
        end
      end # YamlFormatter

      # A JtestR ResultHandler
      # Using this handler we can use RSpec formatters, like html/ci_reporter with JtestR
      # Created for YamlFormatter
      class RSpecResultHandler

        # Workaround for http://jira.codehaus.org/browse/JTESTR-68
        module TestNGResultHandlerMixin
          def onTestSuccess(test_result)
            @result_handler.succeed_single(test_result.name)
          end
        end

        class BacktraceTweaker
          attr_reader :ignore_patterns
          def initialize
            @ignore_patterns = ::Spec::Runner::QuietBacktraceTweaker::IGNORE_PATTERNS.dup
            # ignore jruby/jtestr backtrace
            ignore_patterns << /org\.jruby\.javasupport\.JavaMethod\./
            ignore_patterns << /jtestr.*\.jar!/i << /runner\.rb/
          end

          def clean_up_double_slashes(line)
            line.gsub!('//','/')
          end

          def tweak_backtrace(error)
            return if error.backtrace.nil?
            error.backtrace.collect! do |line|
              clean_up_double_slashes(line)
              ignore_patterns.each do |ignore|
                if line =~ ignore
                  line = nil
                  break
                end
              end
              line
            end
            error.backtrace.compact!
          end
        end

        class << self
          # an rspec reporter used to proxy events to rspec formatters
          attr_reader :reporter
          attr_accessor :test_files

          def init(argv = [], out = STDOUT, err = STDERR)
            ::JtestR::TestNGResultHandler.module_eval { include TestNGResultHandlerMixin }
            rspec_parser = ::Spec::Runner::OptionParser.new(err, out)
            rspec_parser.order!(argv)
            rspec_parser.options.backtrace_tweaker = BacktraceTweaker.new
            @reporter = Spec::Runner::Reporter.new(rspec_parser.options)
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
          attr_accessor :name, :description, :__full_description, :location
        end

        def reporter
          self.class.reporter
        end

        attr_accessor :example_group, :current_example, :current_failure

        def initialize(name, desc, *args)
          self.example_group = ::Spec::Example::ExampleGroup.new(desc)
          example_group.extend ExampleMethods
          example_group.name = name.to_s
          if example_group.name[/Spec/]
            example_group.description = desc.to_s
          else
            example_group.description = name.to_s
          end
          reporter.example_group_started(example_group)
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
          name = name.to_s
          current_example.location = name.to_s
          current_example.name = name.gsub(/(.*)\((.+)\)/, '\2')
          current_example.description = name
          if example_group.name[/Spec/]
            current_example.__full_description = "#{example_group.description} #{name}"
          else
            current_example.__full_description = "#{example_group.name}: #{name}"
          end
          reporter.example_started(current_example)
        end

        def succeed_single(name = nil)
          reporter.example_finished(current_example, nil)
        end

        def fail_single(name = nil)
          current_example.name = current_name
          reporter.example_finished(current_example, current_error)
        end

        def error_single(name = nil)
          current_example.name = current_name
          reporter.example_finished(current_example, current_error)
        end

        def pending_single(name = nil)
          error = ::Spec::Example::ExamplePendingError.new(name)
          reporter.example_finished(current_example, error)
        end

      private
        def detect_file(trace)
          # find first matching test file in stacktrace
          file = nil
          first_pos = nil
          RSpecResultHandler.test_files.each do |f|
            pos = trace.index(f)
            if pos && (first_pos.nil? || pos < first_pos)
              file = f
              first_pos = pos
            end
          end
          file || fail("RSpecResultHandler.detect_file failed: #{trace}")
        end

        def current_name(example = current_example, fault = current_failure)
          return example.name unless fault
          case fault
          when Test::Unit::Error
            detect_file(fault.long_display)
          when Test::Unit::Failure
            detect_file(fault.location.to_s)
          when Spec::Runner::Reporter::Failure
            detect_file(fault.exception.backtrace.to_s)
          else
            example.name
          end
        end

        def current_error(fault = current_failure)
          case fault
          when nil
            nil
          when Test::Unit::Failure
            Error.new(fault.message, fault.location)
          when Test::Unit::Error
            if fault.exception.is_a?(NativeException)
              exception = fault.exception.cause
              bt = exception.stack_trace.to_a
            else
              exception = fault.exception
              bt = exception.backtrace
            end
            Error.new(exception.message, bt)
          when Expectations::Results::Error
            fault.exception
          when Spec::Runner::Reporter::Failure
            ex = fault.exception
            Error.new(ex.message, ex.backtrace)
          when Expectations::Results
            file = fault.file
            line = fault.line
            Error.new(fault.message, ["#{fault.file}:#{fault.line}"])
          else
            if fault.respond_to?(:test_header)
              fault.test_header[/\((.+)\)/]
              test_cls, test_meth = $1.to_s, $`.to_s
              exception = fault.exception
              (class << exception; self; end).module_eval do
                define_method(:backtrace) do
                  (["#{test_cls}:in `#{test_meth}'"] + stackTrace).map { |s| s.to_s }
                end
              end
              exception
            elsif fault.respond_to?(:method)
              test_cls, test_meth = fault.method.test_class.name, fault.method.method_name
              exception = fault.throwable
              (class << exception; self; end).module_eval do
                define_method(:backtrace) do
                  (["#{test_cls}:in `#{test_meth}'"] + stackTrace).map { |s| s.to_s }
                end
              end
              exception
            else
              raise "Cannot handle fault #{fault.class}: #{fault.inspect}"
            end
          end
        end

      end # RSpecResultHandler

    end # TestResult
  end
end
