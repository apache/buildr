require 'core/project'
require 'core/build'
require 'core/compile'


module Buildr

  # The underlying test framework used by TestTask.
  # To add a new test framework, extend TestFramework::Base and add your framework using:
  #   Buildr::TestFramework.add MyFramework
  class TestFramework

    class << self

      # Returns true if the specified test framework exists.
      def has?(name)
        frameworks.any? { |framework| framework.name == name }
      end

      # Select a test framework by its name.
      def select(name)
        frameworks.detect { |framework| framework.name == name }
      end

      # Identify which test framework applies for this project.
      def identify_from(project)
        # Look for a suitable test framework based on the compiled language,
        # which may return multiple candidates, e.g. JUnit and TestNG for Java.
        # Pick the one used in the parent project, if not, whichever comes first.
        candidates = frameworks.select { |framework| framework.supports?(project) }
        parent = project.parent.test.framework if project.parent
        candidates.detect { |framework| framework.name == parent } || candidates.first
      end

      # Adds a test framework to the list of supported frameworks.
      #   
      # For example:
      #   Buildr::TestFramework.add Buildr::JUnit
      def add(framework)
        framework = framework.new if Class === framework
        @frameworks ||= []
        @frameworks |= [framework]
      end
      alias :<< :add

      # Returns a list of available test frameworks.
      def frameworks
        @frameworks ||= []
      end

    end

    # Base class for all test frameworks, with common functionality.  Extend and over-ride as you see fit
    # (see JUnit as an example).
    class Base

      def initialize(args = {})
        args[:name] ||= self.class.name.split('::').last.downcase.to_sym
        args[:requires] ||= []
        args.each { |name, value| instance_variable_set "@#{name}", value }
      end

      attr_accessor :name
      attr_accessor :requires

      def tests(path)
        Dir["#{path}/**/*"]
      end

      def supports?(project)
        false
      end

    end
  
  end


  # The test task controls the entire test lifecycle.
  #
  # You can use the test task in three ways. You can access and configure specific test tasks,
  # e.g. enhance the #compile task, or run code during #setup/#teardown.
  #
  # You can use convenient methods that handle the most common settings. For example, add 
  # dependencies using #with, or include only specific test cases using #include.
  #
  # You can also enhance this task directly. This task will first execute the #compile task, followed
  # by the #setup task, run the unit tests, any other enhancements, and end by executing #teardown.
  #
  # Unit tests are fun from classed compiled by the test.compile class that match the TEST_FILE_PATTERN
  # (i.e. MyClassTest, MyClassTestSuite, etc). The test framework is determined by setting one of the
  # test framework options to true, for example:
  #   test.unsing :testng
  class TestTask < Rake::Task

    class << self

      # Used by the local test and integration tasks to
      # a) Find the local project(s),
      # b) Find all its sub-projects and narrow down to those that have either unit or integration tests,
      # c) Run all the (either unit or integration) tests, and
      # d) Ignore failure if necessary.
      def run_local_tests(integration) #:nodoc:
        Project.local_projects do |project|
          # !(foo ^ bar) tests for equality and accepts nil as false (and select is less obfuscated than reject on ^).
          projects = ([project] + project.projects).select { |project| !(project.test.options[:integration] ^ integration) }
          projects.each do |project|
            puts "Testing #{project.name}" if verbose
            begin
              project.test.invoke
            rescue
              raise unless Buildr.options.test == :all
            end
          end
        end
      end

      # Used by the test/integration rule to only run tests that match the specified names.
      def only_run(tests) #:nodoc:
        tests = tests.map { |name| name =~ /\*/ ? name : "*#{name}*" }
        # Since the test case may reside in a sub-project, we need to set the include/exclude pattern on
        # all sub-projects, but only invoke test on the local project.
        Project.projects.each { |project| project.test.instance_eval { @include = tests ; @exclude.clear } }
      end
    end

    # Default options already set on each test task.
    DEFAULT_OPTIONS = { :fail_on_failure=>true, :fork=>:once, :properties=>{}, :environment=>{} }

    def initialize(*args) #:nodoc:
      super
      @dependencies = FileList[]
      @include = []
      @exclude = []
      @options = OpenObject.new
      parent_task = Project.parent_task(name)
      if parent_task.respond_to?(:options)
        parent_task.options.each { |name, value| @options[name] = value unless @options.has_key?(name) }
      end
      DEFAULT_OPTIONS.each { |name, value| @options[name] = value unless @options.has_key?(name) }
      enhance { run_tests }
    end

    # The dependencies used for running the tests. Includes the compiled files (compile.target)
    # and their dependencies. Will also include anything you pass to #with, shared between the
    # testing compile and run dependencies.
    attr_reader :dependencies

    # *Deprecated*: Use dependencies instead.
    def classpath
      warn_deprecated 'Use dependencies instead.'
      dependencies
    end

    # *Deprecated*: Use dependencies= instead.
    def classpath=(artifacts)
      warn_deprecated 'Use dependencies= instead.'
      self.dependencies = artifacts
    end

    def execute(args) #:nodoc:
      setup.invoke
      begin
        super
      rescue RuntimeError
        raise if options[:fail_on_failure]
      ensure
        teardown.invoke
      end
    end

    # :call-seq:
    #   compile(*sources) => CompileTask
    #   compile(*sources) { |task| .. } => CompileTask
    #
    # The compile task is similar to the Project's compile task. However, it compiles all
    # files found in the src/test/{source} directory into the target/test/{code} directory.
    # This task is executed by the test task before running any test cases.
    #
    # Once the project definition is complete, all dependencies from the regular
    # compile task are copied over, so you only need to specify dependencies
    # specific to your test cases. You can do so by calling #with on the test task.
    # The dependencies used here are also copied over to the junit task.
    def compile(*sources, &block)
      @project.task('test:compile').from(sources).enhance &block
    end
 
    # :call-seq:
    #   resources(*prereqs) => ResourcesTask
    #   resources(*prereqs) { |task| .. } => ResourcesTask
    #
    # Executes by the #compile task to copy resource files over. See Project#resources.
    def resources(*prereqs, &block)
      @project.task('test:resources').enhance prereqs, &block
    end

    # :call-seq:
    #   setup(*prereqs) => task
    #   setup(*prereqs) { |task| .. } => task
    #
    # Returns the setup task. The setup task is executed at the beginning of the test task,
    # after compiling the test files.
    def setup(*prereqs, &block)
      @project.task('test:setup').enhance prereqs, &block
    end

    # :call-seq:
    #   teardown(*prereqs) => task
    #   teardown(*prereqs) { |task| .. } => task
    #
    # Returns the teardown task. The teardown task is executed at the end of the test task.
    def teardown(*prereqs, &block)
      @project.task('test:teardown').enhance prereqs, &block
    end

    # :call-seq:
    #   with(*specs) => self
    #
    # Specify artifacts (specs, tasks, files, etc) to include in the depdenenciest list
    # when compiling and running test cases.
    def with(*artifacts)
      @dependencies |= Buildr.artifacts(artifacts.flatten).uniq
      compile.with artifacts
      self
    end

    # Returns various test options.
    attr_reader :options

    # :call-seq:
    #   using(options) => self
    #
    # Sets various test options from a hash and returns self.  Can also be used to select
    # the test framework.  For example:
    #   test.using :testng, :fork=>:each, :properties=>{ 'url'=>'http://localhost:8080' }
    #
    # Currently supports the following options:
    # * :fail_on_failure -- True to fail on test failure (default is true).
    # * :fork -- Fork test cases (JUnit only).
    # * :properties -- System properties.
    # * :environment -- Environment variables.
    #
    # The :fork option takes the following values:
    # * :once -- Fork one JVM for each project (default).
    # * :each -- Fork one JVM for each test case.
    # * false -- Do not fork, running all test cases in the same JVM.
    def using(*args)
      args.pop.each { |key, value| options[key.to_sym] = value } if Hash === args.last
      args.each do |name|
        if TestFramework.has?(name)
          select name
        else
          options[name.to_sym] = true
        end
      end 
      self
    end

    # :call-seq:
    #   include(*names) => self
    #
    # Include only the specified test cases. Unless specified, the default is to include
    # all test cases. This method accepts multiple arguments and returns self.
    #
    # Test cases are specified using the fully qualified class name. You can also use file-like
    # patterns (glob) to specify collection of files, classes, packages, etc. For example:
    #   test.include 'com.example.FirstTest'
    #   test.include 'com.example.*'
    #   test.include 'com.example.Module*'
    #   test.include '*.{First,Second}Test'
    #
    # By default, all classes that have a name ending with Test or Suite are included.
    # Use these suffixes for your test and test suite classes respectively, to distinguish them
    # from stubs, helper classes, etc. 
    def include(*names)
      @include += names
      self
    end

    # :call-seq:
    #   exclude(*names) => self
    #
    # Exclude the specified test cases. This method accepts multiple arguments and returns self.
    # See #include for the type of arguments you can use.
    def exclude(*names)
      @exclude += names
      self
    end

    # :call-seq:
    #    tests() => strings
    #
    # List of test files to run. Determined by finding all the test failes in the target directory,
    # and reducing based on the include/exclude patterns.
    def tests
      return [] unless compile.target
      fail "No test framework selected" unless @framework
      @files ||= begin
        base = Pathname.new(compile.target.to_s)
        @framework.tests(compile.target.to_s).select { |test| include?(test) }.sort
      end
    end

    # *Deprecated*: Use tests instead.
    def classes
      warn_deprecated 'Use tests instead'
      tests
    end

    # List of failed tests. Set after running the tests.
    attr_reader :failed_tests

    # List of passed tests. Set after running the tests.
    attr_reader :passed_tests

    # :call-seq:
    #   include?(name) => boolean
    #
    # Returns true if the specified class name matches the inclusion/exclusion pattern. Used to determine
    # which tests to execute.
    def include?(name)
      (@include.empty? || @include.any? { |pattern| File.fnmatch(pattern, name) }) &&
        !@exclude.any? { |pattern| File.fnmatch(pattern, name) }
    end

    # :call-seq:
    #   requires() => specs
    #
    # Returns the dependencies for the selected test frameworks. Necessary for compiling and running test cases.
    def requires
      framework ? Array(@framework.requires) : []
    end

    # :call-seq:
    #   framework() => symbol
    #
    # Returns the test framework, e.g. :junit, :testng.
    def framework
      @framework ||= TestFramework.identify_from(@project)
      @framework && @framework.name
    end

    # :call-seq:
    #   report_to() => file
    #
    # Test frameworks that can produce reports, will write them to this directory.
    #
    # This is framework dependent, so unless you use the default test framework, call this method
    # after setting the test framework.
    def report_to
      @report_to ||= file(@project.path_to(:reports, framework)=>self)
    end

  protected

    attr_reader :project

    def associate_with(project)
      @project = project
    end

    def select(name)
      @framework = TestFramework.select(name)
    end

    # :call-seq:
    #   run_tests()
    #
    # Runs the test cases using the selected test framework. Executes as part of the task.
    def run_tests
      rm_rf report_to.to_s
      tests = self.tests
      if tests.empty?
        @passed_tests, @failed_tests = [], []
      else
        puts "Running tests in #{@project.name}" if verbose
        @failed_tests = @framework.run(tests, self, @dependencies.compact.map(&:to_s))
        @passed_tests = tests - @failed_tests
        unless @failed_tests.empty?
          warn "The following tests failed:\n#{@failed_tests.join('\n')}" if verbose
          fail 'Tests failed!'
        end
      end
    end

  end


  # The integration tests task. Buildr has one such task (see Buildr#integration) that runs
  # all tests marked with :integration=>true, and has a setup/teardown tasks separate from
  # the unit tests.
  class IntegrationTestsTask < Rake::Task

    def initialize(*args) #:nodoc:
      super
      @setup = task("#{name}:setup")
      @teardown = task("#{name}:teardown")
      enhance do
        puts 'Running integration tests...'  if verbose
        TestTask.run_local_tests true
      end
    end

    def execute(args) #:nodoc:
      setup.invoke
      begin
        super
      ensure
        teardown.invoke
      end
    end

    # :call-seq:
    #   setup(*prereqs) => task
    #   setup(*prereqs) { |task| .. } => task
    #
    # Returns the setup task. The setup task is executed before running the integration tests.
    def setup(*prereqs, &block)
      @setup.enhance prereqs, &block
    end

    # :call-seq:
    #   teardown(*prereqs) => task
    #   teardown(*prereqs) { |task| .. } => task
    #
    # Returns the teardown task. The teardown task is executed after running the integration tests.
    def teardown(*prereqs, &block)
      @teardown.enhance prereqs, &block
    end

  end


  # Methods added to Project to support compilation and running of test cases.
  module Test

    include Extension

    first_time do
      desc 'Run all test cases'
      task('test') { TestTask.run_local_tests false }

      # This rule takes a suffix and runs that test case in the current project. For example;
      #   buildr test:MyTest
      # will run the test case class com.example.MyTest, if found in the current project.
      #
      # If you want to run multiple test cases, separate tham with a comma. You can also use glob
      # (* and ?) patterns to match multiple tests, e.g. com.example.* to run all test cases in
      # a given package. If you don't specify a glob pattern, asterisks are added for you.
      rule /^test:.*$/ do |task|
        TestTask.only_run task.name.scan(/test:(.*)/)[0][0].split(',')
        task('test').invoke
      end

      task 'build' do |task|
        # Make sure this happens as the last action on the build, so all other enhancements
        # are made to run before starting the test cases.
        task.enhance do
          task('test').invoke unless Buildr.options.test == false
        end
      end

      IntegrationTestsTask.define_task('integration')

      # Similar to test:[pattern] but for integration tests.
      rule /^integration:.*$/ do |task|
        unless task.name.split(':')[1] =~ /^(setup|teardown)$/
          TestTask.only_run task.name.scan(/integration:(.*)/)[0][0].split(',')
          task('integration').invoke
        end
      end

    end
    
    before_define do |project|
      # Define a recursive test task, and pass it a reference to the project so it can discover all other tasks.
      test = TestTask.define_task('test')
      test.send :associate_with, project

      # Similar to the regular resources task but using different paths.
      resources = ResourcesTask.define_task('test:resources')
      project.path_to(:src, :test, :resources).tap { |dir| resources.from dir if File.exist?(dir) }
      resources.filter.into project.path_to(:target, :test, :resources)

      # Similar to the regular compile task but using different paths.
      compile = CompileTask.define_task('test:compile'=>[project.compile, resources])
      compile.send :associate_with, project, :test
      test.enhance [compile]

      # Define these tasks once, otherwise we may get a namespace error.
      test.setup ; test.teardown
    end

    after_define do |project|
      test = project.test
      # Dependency on compiled code, its dependencies and resources.
      test.with project.compile.dependencies, Array(project.compile.target) if project.compile.target
      test.with Array(project.resources.target)
      # Dependency on compiled test cases and resources.  Dependencies added using with.
      test.dependencies.concat Array(test.compile.target) if test.compile.target
      test.dependencies.concat Array(test.resources.target)
      # Test framework dependency.
      test.with test.requires

      project.clean do
        verbose(false) do
          rm_rf test.compile.target.to_s if test.compile.target
          rm_rf test.report_to.to_s
        end
      end
    end


    # :call-seq:
    #   test(*prereqs) => TestTask
    #   test(*prereqs) { |task| .. } => TestTask
    #
    # Returns the test task. The test task controls the entire test lifecycle.
    #
    # You can use the test task in three ways. You can access and configure specific
    # test tasks, e.g. enhance the compile task by calling test.compile, setup for
    # the test cases by enhancing test.setup and so forth.
    #
    # You can use convenient methods that handle the most common settings. For example,
    # add dependencies using test.with, or include only specific test cases
    # using test.include.
    #
    # You can also enhance this task directly. This method accepts a list of arguments
    # that are used as prerequisites and an optional block that will be executed by the
    # test task.
    #
    # This task compiles the project and the test cases (in that order) before running any tests.
    # It execute the setup task, runs all the test cases, any enhancements, and ends with the
    # teardown tasks.
    def test(*prereqs, &block)
      task('test').enhance prereqs, &block
    end
  
    # :call-seq:
    #   integration() { |task| .... }
    #   integration() => IntegrationTestTask
    #
    # Use this method to return the integration tests task, or enhance it with a block to execute.
    #
    # There is one integration tests task you can execute directly, or as a result of running the package
    # task (or tasks that depend on it, like install and deploy). It contains all the tests marked with
    # :integration=>true, all other tests are considered unit tests and run by the test task before packaging.
    # So essentially: build=>test=>packaging=>integration=>install/deploy.
    #
    # You add new test cases from projects that define integration tests using the regular test task,
    # but with the following addition:
    #   test.using :integration
    #
    # Use this method to enhance the setup and teardown tasks that are executed before (and after) all
    # integration tests are run, for example, to start a Web server or create a database.
    def integration(*deps, &block)
      Rake::Task['rake:integration'].enhance deps, &block
    end

  end


  # :call-seq:
  #   integration() { |task| .... }
  #   integration() => IntegrationTestTask
  #
  # Use this method to return the integration tests task.
  def integration(*deps, &block)
    Rake::Task['rake:integration'].enhance deps, &block
  end

  class Options

    # Runs test cases after the build when true (default). This forces test cases to execute
    # after the build, including when running build related tasks like install, deploy and release.
    #
    # Set to false to not run any test cases. Set to :all to run all test cases, ignoring failures.
    #
    # This option is set from the environment variable 'test', so you can also do:

    # Returns the test option (environment variable TEST). Possible values are:
    # * :false -- Do not run any test cases (also accepts 'no' and 'skip').
    # * :true -- Run all test cases, stop on failure (default if not set).
    # * :all -- Run all test cases, ignore failures.
    def test
      case value = ENV['TEST'] || ENV['test']
      when /^(no|off|false|skip)$/i
        false
      when /^all$/i
        :all
      when /^(yes|on|true)$/i, nil
        true
      else
        warn "Expecting the environment variable test to be 'no' or 'all', not sure what to do with #{value}, so I'm just going to run all the test cases and stop at failure."
        true
      end
    end

    # Sets the test option (environment variable TEST). Possible values are true, false or :all.
    #
    # You can also set this from the environment variable, e.g.:
    #
    #   buildr          # With tests
    #   buildr test=no  # Without tests
    #   buildr test=all # Ignore failures
    #   set TEST=no
    #   buildr          # Without tests
    def test=(flag)
      ENV['test'] = nil
      ENV['TEST'] = flag.to_s
    end

  end

  task('help') do
    puts <<-HELP

To run a full build without running any test cases:
  buildr test=no
To run specific test case:
  buildr test:MyTest
To run integration tests:
  buildr integration
    HELP
  end

end


class Buildr::Project
  include Buildr::Test
end
