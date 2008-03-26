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


# This file gets loaded twice when running 'spec spec/*' and not with pleasent results,
# so ignore the second attempt to load it.
unless self.class.const_defined?('SpecHelpers')

  require 'rubygems'
  $LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))
  require 'buildr'

  # Load additional files for optional specs
  if rspec_options.argv.any? { |s| s =~ /groovy_compilers_spec/ }
    require 'java/groovyc'
  end

  require File.expand_path('sandbox', File.dirname(__FILE__))

  module SpecHelpers

    include Checks::Matchers

    module ::Kernel #:nodoc:
      def warn(message)
        $warning ||= []
        $warning << message
      end

      alias :warn_deprecated_without_capture :warn_deprecated
      def warn_deprecated(message)
        verbose(true) { warn_deprecated_without_capture message }
      end
    end

    class WarningMatcher
      def initialize(message)
        @expect = message
      end

      def matches?(target)
        $warning = []
        target.call
        return Regexp === @expect ? $warning.join('\n') =~ @expect : $warning.include?(@expect.to_s)
      end

      def failure_message
        $warning ? "Expected warning #{@expect.source}, found #{$warning}" : "Expected warning #{@expect.source}, no warning issued"
      end

      def negative_failure_message
        "Found unexpected #{$warning}"
      end
    end

    # Tests if a warning was issued. You can use a string or regular expression.
    #
    # For example:
    #   lambda { warn 'ze test' }.should warn_that(/ze test/)
    def warn_that(message)
      WarningMatcher.new message
    end


    class ::Rake::Task
      alias :execute_without_a_record :execute
      def execute(args)
        $executed ||= []
        $executed << name
        execute_without_a_record args
      end
    end

    class InvokeMatcher
      def initialize(*tasks)
        @expecting = tasks.map { |task| [task].flatten.map(&:to_s) }
      end

      def matches?(target)
        $executed = []
        target.call
        return false unless all_ran?
        return !@but_not.any_ran? if @but_not
        return true
      end

      def failure_message
        return @but_not.negative_failure_message if all_ran? && @but_not
        "Expected the tasks #{expected} to run, but #{remaining} did not run, or not in the order we expected them to."
      end

      def negative_failure_message
        if all_ran?
          "Expected the tasks #{expected} to not run, but they all ran."
        else
          "Expected the tasks #{expected} to not run, and all but #{remaining} ran."
        end 
      end

      def but_not(*tasks)
        @but_not = InvokeMatcher.new(*tasks)
        self
      end

    protected

      def expected
        @expecting.map { |tests| tests.join('=>') }.join(', ')
      end

      def remaining
        @remaining.map { |tests| tests.join('=>') }.join(', ')
      end

      def all_ran?
        @remaining ||= $executed.inject(@expecting) do |expecting, executed|
          expecting.map { |tasks| tasks.first == executed ? tasks[1..-1] : tasks }.reject(&:empty?)
        end
        @remaining.empty?
      end

      def any_ran?
        all_ran?
        @remaining.size < @expecting.size
      end

    end

    # Tests that all the tasks ran, in the order specified. Can also be used to test that some
    # tasks and not others ran.
    #
    # Takes a list of arguments. Each argument can be a task name, matching only if that task ran.
    # Each argument can be an array of task names, matching only if all these tasks ran in that order.
    # So run_tasks('foo', 'bar') expects foo and bar to run in any order, but run_task(['foo', 'bar'])
    # expects foo to run before bar.
    #
    # You can call but_not on the matchers to specify that certain tasks must not execute.
    #
    # For example:
    #   # Either task
    #   lambda { task('compile').invoke }.should run_tasks('compile', 'resources')
    #   # In that order
    #   lambda { task('build').invoke }.should run_tasks(['compile', 'test'])
    #   # With exclusion
    #   lambda { task('build').invoke }.should run_tasks('compile').but_not('install')
    def run_tasks(*tasks)
      InvokeMatcher.new *tasks
    end

    # Tests that a task ran. Similar to run_tasks, but accepts a single task name.
    #
    # For example:
    #   lambda { task('build').invoke }.should run_task('test')
    def run_task(task)
      InvokeMatcher.new [task]
    end

    class UriPathMatcher
      def initialize(re)
        @expression = re
      end

      def matches?(uri)
        @uri = uri
        uri.path =~ @expression
      end

      def description
        "URI with path matching #{@expression}"
      end
    end
    
    # Matches a parsed URI's path against the given regular expression
    def uri(re)
      UriPathMatcher.new(re)
    end


    class AbsolutePathMatcher
      def initialize(path)
        @expected = File.expand_path(path.to_s)
      end

      def matches?(path)
        @provided = File.expand_path(path.to_s)
        @provided == @expected
      end

      def failure_message
        "Expected path #{@expected}, but found path #{@provided}"
      end

      def negative_failure_message
        "Expected a path other than #{@expected}"
      end
    end

    def point_to_path(path)
      AbsolutePathMatcher.new(path)
    end


    def suppress_stdout
      stdout = $stdout
      $stdout = StringIO.new
      begin
        yield
      ensure
        $stdout = stdout
      end
    end

    def dryrun
      Rake.application.options.dryrun = true
      begin
        suppress_stdout { yield }
      ensure
        Rake.application.options.dryrun = false
      end
    end

    # We run tests with tracing off. Then things break. And we need to figure out what went wrong.
    # So just use trace() as you would use verbose() to find and squash the bug.
    def trace(value = nil)
      old_value = Rake.application.options.trace
      Rake.application.options.trace = value unless value.nil?
      if block_given?
        begin
          yield
        ensure
          Rake.application.options.trace = old_value
        end
      end
      Rake.application.options.trace
    end

    # Change the Rakefile original directory, faking invocation from a different directory.
    def in_original_dir(dir)
      begin
        original_dir = Rake.application.original_dir
        Rake.application.instance_eval { @original_dir = File.expand_path(dir) }
        yield
      ensure
        Rake.application.instance_eval { @original_dir = original_dir }
      end 
    end


    # Buildr's define method creates a project definition but does not evaluate it
    # (that happens once the Rakefile is loaded), and we include Buildr's define in
    # the test context so we can use it without prefixing with Buildr. This just patches
    # define to evaluate the project definition before returning it.
    def define(name, properties = nil, &block) #:yields:project
      Project.define(name, properties, &block).tap { |project| project.invoke }
    end

  end


  # Allow using matchers within the project definition.
  class Buildr::Project
    include ::Spec::Matchers, SpecHelpers
  end


  Spec::Runner.configure do |config|
    # Make all Buildr methods accessible from test cases, and add various helper methods.
    config.include Buildr, SpecHelpers

    # Sanbdox Rake/Buildr for each test.
    config.include Sandbox
  end

end
