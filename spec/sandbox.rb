# This file is required twice when running spec test/*.
unless defined?(Buildr)

  require 'rubygems'
  #require "rake"
  $LOAD_PATH.unshift File.expand_path("#{File.dirname(__FILE__)}/../lib")
  require File.join(File.dirname(__FILE__), "../lib", "buildr.rb")


  # The local repository we use for testing is void of any artifacts, which will break given
  # that the code requires several artifacts. So we establish them first using the real local
  # repository and cache these across test cases.
  repositories.remote << "http://repo1.maven.org/maven2"
  Java.wrapper.load # Anything added to the classpath.
  artifacts(TestTask::JUNIT_REQUIRES, TestTask::TESTNG_REQUIRES, Java::JMock::JMOCK_REQUIRES).each { |a| file(a).invoke }
  task("buildr:initialize").invoke


  module Buildr

    module Matchers

      include Checks::Matchers

      module ::Kernel #:nodoc:
        def warn(message)
          $warning ||= []
          $warning << message
        end

        def warn_deprecated_with_capture(message)
          verbose(true) { warn_deprecated_without_capture message }
        end
        alias_method_chain :warn_deprecated, :capture
      end

      class WarningMatcher
        def initialize(message)
          @expect = message
        end

        def matches?(target)
          $warning = []
          target.call
          return Regexp === @expect ? $warning.join("\n") =~ @expect : $warning.include?(@expect.to_s)
        end

        def failure_message()
          $warning ? "Expected warning #{@expect.source}, found #{$warning}" : "Expected warning #{@expect.source}, no warning issued"
        end
      end

      # Tests if a warning was issued. You can use a string or regular expression.
      #
      # For example:
      #   lambda { warn "ze test" }.should warn_that(/ze test/)
      def warn_that(message)
        WarningMatcher.new message
      end


      class ::Rake::Task
        def execute_with_a_record(args)
          $executed ||= []
          $executed << name
          execute_without_a_record args
        end
        alias_method_chain :execute, :a_record
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

        def failure_message()
          return @but_not.negative_failure_message if all_ran? && @but_not
          "Expected the tasks #{expected} to run, but #{remaining} did not run, or not in the order we expected them to."
        end

        def negative_failure_message()
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

        def expected()
          @expecting.map { |tests| tests.join("=>") }.join(", ")
        end

        def remaining()
          @remaining.map { |tests| tests.join("=>") }.join(", ")
        end

        def all_ran?()
          @remaining ||= $executed.inject(@expecting) do |expecting, executed|
            expecting.map { |tasks| tasks.first == executed ? tasks.tail : tasks }.reject(&:empty?)
          end
          @remaining.empty?
        end

        def any_ran?()
          all_ran?
          @remaining.size < @expecting.size
        end

      end

      # Tests that all the tasks ran, in the order specified. Can also be used to test that some
      # tasks and not others ran.
      #
      # Takes a list of arguments. Each argument can be a task name, matching only if that task ran.
      # Each argument can be an array of task names, matching only if all these tasks ran in that order.
      # So run_tasks("foo", "bar") expects foo and bar to run in any order, but run_task(["foo", "bar"])
      # expects foo to run before bar.
      #
      # You can call but_not on the matchers to specify that certain tasks must not execute.
      #
      # For example:
      #   # Either task
      #   lambda { task("compile").invoke }.should run_tasks("compile", "resources")
      #   # In that order
      #   lambda { task("build").invoke }.should run_tasks(["compile", "test"])
      #   # With exclusion
      #   lambda { task("build").invoke }.should run_tasks("compile").but_not("install")
      def run_tasks(*tasks)
        InvokeMatcher.new *tasks
      end

      # Tests that a task ran. Similar to run_tasks, but accepts a single task name.
      #
      # For example:
      #   lambda { task("build").invoke }.should run_task("test")
      def run_task(task)
        InvokeMatcher.new task.to_a.first
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

    end


    module Helpers

      def suppress_stdout()
        stdout = $stdout
        $stdout = StringIO.new
        begin
          yield
        ensure
          $stdout = stdout
        end
      end

      def dryrun()
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


    # We need to run all tests inside a sandbox, tacking a snapshot of Rake/Buildr before the test,
    # and restoring everything to its previous state after the test. Damn state changes.
    module Sandbox

      def sandbox()
        @sandbox = {}
        # During teardown we get rid of all the tasks and start with a clean slate.
        # Unfortunately, we also get rid of tasks we need, like build, clean, etc.
        # Here we capture them in their original form, recreated during teardown.
        @sandbox[:tasks] = Rake.application.tasks.collect do |original|
          prerequisites = original.prerequisites.clone
          actions = original.instance_eval { @actions }.clone
          lambda do
            original.class.send(:define_task, original.name=>prerequisites).tap do |task|
              task.comment = original.comment
              actions.each { |action| task.enhance &action }
            end
          end
        end
        @sandbox[:rules] = Rake.application.instance_variable_get(:@rules).clone

        # Create a temporary directory where we can create files, e.g,
        # for projects, compilation. We need a place that does not depend
        # on the current directory.
        @test_dir = File.expand_path("tmp", File.dirname(__FILE__))
        FileUtils.mkpath @test_dir
        # Move to the work directory and make sure Rake thinks of it as the Rakefile directory.
        @sandbox[:pwd] = Dir.pwd
        Dir.chdir @test_dir
        @sandbox[:original_dir] = Rake.application.original_dir 
        Rake.application.instance_eval { @original_dir = Dir.pwd }
        Rake.application.instance_eval { @rakefile = File.join(Dir.pwd, 'buildfile') }
        
        # Later on we'll want to lose all the on_define created during the test.
        @sandbox[:on_define] = Project.class_eval { (@on_define || []).dup }

        # Create a local repository we can play with. However, our local repository will be void
        # of some essential artifacts (e.g. JUnit artifacts required by build task), so we create
        # these first (see above) and keep them across test cases.
        @sandbox[:artifacts] = Artifact.class_eval { @artifacts }.clone
        Buildr.repositories.local = File.join(@test_dir, "repository")

        @sandbox[:env_keys] = ENV.keys
        ["DEBUG", "TEST", "HTTP_PROXY", "USER"].each { |k| ENV.delete(k) ; ENV.delete(k.downcase) }

        # Don't output crap to the console.
        trace false
        verbose false
      end

      # Call this from teardown.
      def reset()
        # Remove testing local repository, and reset all repository settings.
        Buildr.repositories.local = nil
        Buildr.repositories.remote = nil
        Buildr.repositories.release_to = nil
        Buildr.options.proxy.http = nil
        Buildr.instance_eval { @profiles = nil }

        # Get rid of all the projects and the on_define blocks we used.
        Project.clear
        on_define = @sandbox[:on_define]
        Project.class_eval { @on_define = on_define }

        # Switch back Rake directory.
        Dir.chdir @sandbox[:pwd]
        original_dir = @sandbox[:original_dir]
        Rake.application.instance_eval { @original_dir = original_dir }
        FileUtils.rm_rf @test_dir

        # Get rid of all the tasks and restore the default tasks.
        Rake::Task.clear
        @sandbox[:tasks].each { |block| block.call }
        Rake.application.instance_variable_set :@rules, @sandbox[:rules]

        # Get rid of all artifacts and out test directory.
        @sandbox[:artifacts].tap { |artifacts| Artifact.class_eval { @artifacts = artifacts } }

        # Restore options.
        Buildr.options.test = nil
        (ENV.keys - @sandbox[:env_keys]).each { |key| ENV.delete key }
      end

    end

  end

  # Allow using matchers within the project definition.
  class Buildr::Project
    include ::Spec::Matchers, ::Buildr::Matchers
  end

  Spec::Runner.configure do |config|
    # Make all Buildr methods accessible from test cases, and add various helper methods.
    config.include Buildr, Buildr::Helpers, Buildr::Matchers

    # Sanbdox Rake/Buildr for each test.
    config.include Buildr::Sandbox
    config.before(:each) { sandbox }
    config.after(:each) { reset }
  end

end
