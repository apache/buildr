require "core/build"
require "java/compile"
require "java/ant"
require "core/help"


module Buildr
  module Java

    # *Deprecated:* Use the test task directly instead of calling test.junit.
    class JUnitTask < Rake::Task #:nodoc:

      # The classpath used for running the tests. Includes the compile classpath,
      # compiled classes (target). For everything else, add by calling #with.
      attr_accessor :classpath

      def initialize(*args) #:nodoc:
        super
        @parent = Rake::Task["#{name.split(":")[0...-1].join(":")}"]
      end

      # :call-seq:
      #   include(*classes) => self
      #
      # Include only the specified test cases. Unless specified, the default is to include
      # all test cases. This method accepts multiple arguments and returns self.
      #
      # Test cases are specified using the fully qualified class name. You can also use file-like
      # patterns (glob) to specify collection of classes. For example:
      #   test.include "com.example.FirstTest"
      #   test.include "com.example.*"
      #   test.include "com.example.Module*"
      #   test.include "*.{First,Second}Test"
      #
      # By default, all classes that have a name ending with Test or Suite are included.
      # Use these suffixes for your test and test suite classes respectively, to distinguish them
      # from stubs, helper classes, etc. 
      def include(*classes)
        @parent.include *classes
        self
      end

      # :call-seq:
      #   exclude(*classes) => self
      #
      # Exclude the specified test cases. This method accepts multiple arguments and returns self.
      # See #include for the type of arguments you can use.
      def exclude(*classes)
        @parent.exclude *classes
        self
      end

      # :call-seq:
      #   from(*paths) => self
      #
      # Specify one or more directories that include test cases. 
      def from(*files)
        self
      end

      # :call-seq:
      #   with(*specs) => self
      #
      # Specify artifacts (specs, tasks, files, etc) to include in the classpath when running
      # the test cases.
      def with(*files)
        (@parent.options[:classpath] ||= []).concat files.flatten
        self
      end

      # Returns the JUnit options.
      def options()
        @parent.options
      end

      # :call-seq:
      #   using(options) => self
      #
      # Sets the JUnit options from a hash and returns self. Right now supports passing :properties to JUnit,
      # and :java_args to the JVM.
      #
      # For example:
      #   test.junit.using :properties=>{ "root"=>base_dir }
      def using(options)
        @parent.using options
        self
      end

    end


    # The test task controls the entire test lifecycle.
    #
    # You can use the test task in three ways. You can access and configure specific test tasks,
    # e.g. enhance the #compile task, or run code during #setup/#teardown.
    #
    # You can use convenient methods that handle the most common settings. For example, add classpath
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

      # List of supported test framework, first one being a default. Test frameworks are added by
      # including them in TestTask (e.g. JUnit, TestNG).
      TEST_FRAMEWORKS = []

      # Default options already set on each test task.
      DEFAULT_OPTIONS = { :fail_on_failure=>true, :fork=>:once, :properties=>{}, :environment=>{} }

      # JMock version..
      JMOCK_VERSION = "1.2.0"
      # JMock specification.
      JMOCK_REQUIRES = "jmock:jmock:jar:#{JMOCK_VERSION}"

      # The classpath used for running the tests. Includes the compiled classes (compile.target) and
      # their classpath dependencies. Will also include anything you pass to #with, shared between the
      # testing compile and run classpath dependencies.
      attr_reader :classpath

      def initialize(*args) #:nodoc:
        super
        @classpath = []
        @include = []
        @exclude = []
        parent = Project.task_in_parent_project(name)
        @options = parent && parent.respond_to?(:options) ? parent.options.clone : DEFAULT_OPTIONS.clone
        enhance { run_tests }
      end

      def execute() #:nodoc:
        setup.invoke
        begin
          super
          @project.task("test:junit").invoke # In case someone enhanced it
        rescue RuntimeError
          raise if options[:fail_on_failure]
        ensure
          teardown.invoke
        end
      end

      # *Deprecated* Add a prerequisite to the compile task instead.
      def prepare(*prereqs, &block)
        warn_deprecated "Add a prerequisite to the compile task instead of using the prepare task."
        @project.task("test:prepare").enhance prereqs, &block
      end

      # :call-seq:
      #   compile(*sources) => CompileTask
      #   compile(*sources) { |task| .. } => CompileTask
      #
      # The compile task is similar to the Project's compile task. However, it compiles all
      # files found in the src/java/test directory into the target/test-classes directory.
      # This task is executed by the test task before running any test cases.
      #
      # Once the project definition is complete, all classpath dependencies from the regular
      # compile task are copied over, so you only need to specify classpath dependencies
      # specific to your test cases. You can do so by calling #with on the test task.
      # The classpath dependencies used here are also copied over to the junit task.
      def compile(*sources, &block)
        @project.task("test:compile").from(sources).enhance &block
      end
   
      # :call-seq:
      #   resources(*prereqs) => ResourcesTask
      #   resources(*prereqs) { |task| .. } => ResourcesTask
      #
      # Executes by the #compile task to copy resource files over. See Project#resources.
      def resources(*prereqs, &block)
        @project.task("test:resources").enhance prereqs, &block
      end

      # *Deprecated* Use the test task directly instead of calling test.junit.
      def junit()
        warn_deprecated "Use the test task directly instead of calling test.junit."
        @project.task("test:junit")
      end

      # :call-seq:
      #   setup(*prereqs) => task
      #   setup(*prereqs) { |task| .. } => task
      #
      # Returns the setup task. The setup task is executed at the beginning of the test task,
      # after compiling the test files.
      def setup(*prereqs, &block)
        @project.task("test:setup").enhance prereqs, &block
      end

      # :call-seq:
      #   teardown(*prereqs) => task
      #   teardown(*prereqs) { |task| .. } => task
      #
      # Returns the teardown task. The teardown task is executed at the end of the test task.
      def teardown(*prereqs, &block)
        @project.task("test:teardown").enhance prereqs, &block
      end

      # :call-seq:
      #   with(*specs) => self
      #
      # Specify artifacts (specs, tasks, files, etc) to include in the classpath when compiling
      # and running test cases.
      def with(*artifacts)
        @classpath |= Buildr.artifacts(artifacts.flatten).uniq
        compile.with artifacts
        self
      end

      # Returns various test options.
      attr_reader :options

      # :call-seq:
      #   using(options) => self
      #
      # Sets various test options and returns self. Accepts a hash of options, or symbols (a symbol sets that
      # option to true). For example:
      #   test.using :testng, :fork=>:each, :properties=>{ "url"=>"http://localhost:8080" }
      #
      # Currently supports the following options:
      # * :fail_on_failure -- True to fail on test failure (default is true).
      # * :fork -- Fork test cases (JUnit only).
      # * :java_args -- Java arguments when forking a new JVM.
      # * :properties -- System properties.
      # * :environment -- Environment variables.
      #
      # The :fork option takes the following values:
      # * :once -- Fork one JVM for each project (default).
      # * :each -- Fork one JVM for each test case.
      # * false -- Do not fork, running all test cases in the same JVM.
      def using(*args)
        args.pop.each { |key, value| options[key.to_sym] = value } if Hash === args.last
        args.each { |key| options[key.to_sym] = true }
        self
      end

      # :call-seq:
      #   include(*classes) => self
      #
      # Include only the specified test cases. Unless specified, the default is to include
      # all test cases. This method accepts multiple arguments and returns self.
      #
      # Test cases are specified using the fully qualified class name. You can also use file-like
      # patterns (glob) to specify collection of classes. For example:
      #   test.include "com.example.FirstTest"
      #   test.include "com.example.*"
      #   test.include "com.example.Module*"
      #   test.include "*.{First,Second}Test"
      #
      # By default, all classes that have a name ending with Test or Suite are included.
      # Use these suffixes for your test and test suite classes respectively, to distinguish them
      # from stubs, helper classes, etc. 
      def include(*classes)
        @include += classes
        self
      end

      # :call-seq:
      #   exclude(*classes) => self
      #
      # Exclude the specified test cases. This method accepts multiple arguments and returns self.
      # See #include for the type of arguments you can use.
      def exclude(*classes)
        @exclude += classes
        self
      end

      # :call-seq:
      #    classes() => strings
      #
      # List of test classes to run. Determined by finding all the test classes in the target directory,
      # and reducing based on the include/exclude patterns.
      def classes()
        base = Pathname.new(compile.target.to_s)
        patterns = self.class.const_get("#{framework.to_s.upcase}_TESTS_PATTERN").to_a
        FileList[patterns.map { |pattern| "#{base}/**/#{pattern}.class" }].
          map { |file| Pathname.new(file).relative_path_from(base).to_s.ext("").gsub(File::SEPARATOR, ".") }.
          select { |name| include?(name) }.reject { |name| name =~ /\$/ }.sort
      end

      # List of failed test classes. Set after running the tests.
      attr_reader :failed_tests

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
      #   requires() => classpath
      #
      # Returns the classpath for the selected test frameworks. Necessary for compiling and running test cases.
      def requires()
        self.class.const_get("#{framework.to_s.upcase}_REQUIRES").to_a + [JMOCK_REQUIRES]
      end

      # :call-seq:
      #   framework() => symbol
      #
      # Returns the test framework, e.g. :junit, :testng.
      def framework()
        @framework ||= TEST_FRAMEWORKS.detect { |name| options[name] } || TEST_FRAMEWORKS.first
      end

      # :call-seq:
      #   report_to() => file
      #
      # Test frameworks that can produce reports, will write them to this directory.
      #
      # This is framework dependent, so unless you use the default test framework, call this method
      # after setting the test framework.
      def report_to()
        @report_to ||= file(@project.path_to(:reports, "#{framework}")=>self)
      end

    protected

      # :call-seq:
      #   run_tests()
      #
      # Runs the test cases using the selected test framework. Executes as part of the task.
      def run_tests()
        classes = self.classes
        if classes.empty?
          @failed_tests = []
        else
          puts "Running tests in #{@project.name}" if verbose
          @failed_tests = send("#{framework}_run",
            :classes    => classes,
            :classpath  => @classpath + [compile.target],
            :properties => { 'baseDir' => compile.target.to_s }.merge(options[:properties] || {}),
            :environment=> options[:environment] || {},
            :java_args  => options[:java_args] || Buildr.options.java_args)
          unless @failed_tests.empty?
            warn "The following tests failed:\n#{@failed_tests.join("\n")}" if verbose
            fail "Tests failed!"
          end
        end
      end

    end


    # The JUnit test framework. This is the default test framework, but you can force it by
    # adding the following to your project:
    #   test.using :testng
    #
    # You can use the report method to control the junit:report task.
    module JUnit

      # Used by the junit:report task. Access through JUnit#report if you want to set various
      # options for that task, for example:
      #   JUnit.report.frames = false
      class Report

        # Ant-Trax required for running the JUnitReport task.
        Java.wrapper.setup { |jw| jw.classpath << "org.apache.ant:ant-trax:jar:#{Ant::VERSION}" }

        # Parameters passed to the Ant JUnitReport task.
        attr_reader :params
        # True (default) to produce a report using frames, false to produce a single-page report.
        attr_accessor :frames
        # Directory for the report style (defaults to using the internal style).
        attr_accessor :style_dir
        # Target directory for generated report.
        attr_accessor :target

        def initialize()
          @params = {}
          @frames = true
          @target = "reports/junit"
        end

        # :call-seq:
        #   generate(projects, target?)
        #
        # Generates a JUnit report for these projects (must run JUnit tests first) into the
        # target directory. You can specify a target, or let it pick the default one from the
        # target attribute.
        def generate(projects, target = @target.to_s)
          html_in = File.join(target, "html")
          rm_rf html_in ; mkpath html_in
          
          Buildr.ant("junit-report") do |ant|
            ant.junitreport :todir=>target do
              projects.select { |project| project.test.framework == :junit }.
                map { |project| project.test.report_to.to_s }.select { |path| File.exist?(path) }.
                each { |path| ant.fileset(:dir=>path) { ant.include :name=>"TEST-*.xml" }  }
              options = { :format=>frames ? "frames" : "noframes" }
              options[:styledir] = style_dir if style_dir
              ant.report options.merge(:todir=>html_in) do
                params.each { |key, value| ant.param :name=>key, :expression=>value }
              end
            end
          end
        end

      end

      # JUnit version number.
      JUNIT_VERSION = "4.3.1"
      # JUnit specification.
      JUNIT_REQUIRES = "junit:junit:jar:#{JUNIT_VERSION}"
      # Pattern for selecting JUnit test classes. Regardless of include/exclude patterns, only classes
      # that match this pattern are used.
      JUNIT_TESTS_PATTERN = [ "Test*", "*Test" ]

      # Ant-JUnit requires for JUnit and JUnit reports tasks.
      Java.wrapper.setup { |jw| jw.classpath << "org.apache.ant:ant-junit:jar:#{Ant::VERSION}" }

      class << self

        # :call-seq:
        #    report()
        #
        # Returns the Report object used by the junit:report task. You can use this object to set
        # various options that affect your report, for example:
        #   JUnit.report.frames = false
        #   JUnit.report.params["title"] = "My App"
        def report()
          @report ||= Report.new
        end

        def included(mod)
          mod::TEST_FRAMEWORKS << :junit
        end
        private :included

      end

    private

      def junit_run(args)
        rm_rf report_to.to_s ; mkpath report_to.to_s
        # Use Ant to execute the Junit tasks, gives us performance and reporting.
        Buildr.ant("junit") do |ant|
          case options[:fork]
          when false
            forking = {}
          when :each
            forking = { :fork=>true, :forkmode=>"perTest" }
          when true, :once
            forking = { :fork=>true, :forkmode=>"once" }
          else
            fail "Option fork must be :once, :each or false."
          end
          ant.junit forking.merge(:clonevm=>options[:clonevm] || false, :dir=>@project.path_to) do
            ant.classpath :path=>args[:classpath].map(&:to_s).each { |path| file(path).invoke }.join(File::PATH_SEPARATOR)
            args[:properties].each { |key, value| ant.sysproperty :key=>key, :value=>value }
            args[:environment].each { |key, value| ant.env :key=>key, :value=>value }
            java_args = args[:java_args]
            java_args = java_args.split(" ") if String === java_args
            java_args.each { |value| ant.jvmarg :value=>value } if java_args
            ant.formatter :type=>"plain"
            ant.formatter :type=>"xml"
            ant.formatter :type=>"plain", :usefile=>false # log test
            ant.formatter :type=>"xml"
            ant.batchtest :todir=>report_to.to_s, :failureproperty=>"failed" do
              ant.fileset :dir=>compile.target.to_s do
                args[:classes].each { |cls| ant.include :name=>cls.gsub(".", "/").ext("class") }
              end
            end
          end
          return [] unless ant.project.getProperty("failed")
        end
        # But Ant doesn't tell us what went kaput, so we'll have to parse the test files.
        args[:classes].inject([]) do |failed, name|
          if report = File.read(File.join(report_to.to_s, "TEST-#{name}.txt")) rescue nil
            # The second line (if exists) is the status line and we scan it for its values.
            status = (report.split("\n")[1] || "").scan(/(run|failures|errors):\s*(\d+)/i).
              inject(Hash.new(0)) { |hash, pair| hash[pair[0].downcase.to_sym] = pair[1].to_i ; hash }
            failed << name if status[:failures] > 0 || status[:errors] > 0
          end
          failed
        end
      end

      namespace "junit" do
        desc "Generate JUnit tests report in #{report.target}"
        task("report") do |task|
          report.generate Project.projects
          puts "Generated JUnit tests report in #{report.target}"
        end
      end

      task("clean") { rm_rf report.target.to_s }

    end


    # The TestNG test framework. Use by adding the following to your project:
    #   test.using :testng
    module TestNG

      # TestNG version number.
      TESTNG_VERSION = "5.5"
      # TestNG specification.
      TESTNG_REQUIRES = "org.testng:testng:jar:jdk15:#{TESTNG_VERSION}"
      # Pattern for selecting TestNG test classes. Regardless of include/exclude patterns, only classes
      # that match this pattern are used.
      TESTNG_TESTS_PATTERN = [ "Test*", "*Test", "*TestCase" ]

      class << self

        def included(mod)
          mod::TEST_FRAMEWORKS << :testng
        end
        private :included

      end

    private

      def testng_run(args)
        cmd_args = [ "org.testng.TestNG", "-sourcedir", compile.sources.join(";"), "-suitename", @project.name ]
        cmd_args << "-d" << report_to.to_s
        cmd_options = args.only(:classpath, :properties, :java_args)
        args[:classes].inject([]) do |failed, test|
          begin
            Buildr.java cmd_args, "-testclass", test, cmd_options.merge(:name=>test)
            failed
          rescue
            failed << test
          end
        end
      end

    end

    class TestTask ; include JUnit ; include TestNG ; end

  end


  class Project

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
    # add classpath dependencies using test.with, or include only specific test cases
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
      task("test").enhance prereqs, &block
    end
  
  end
      

  Project.on_define do |project|
    # Define a recursive test task, and pass it a reference to the project so it can discover all other tasks.
    Java::TestTask.define_task("test")
    project.test.instance_eval { instance_variable_set :@project, project }
    #project.recursive_task("test")
    # Similar to the regular resources task but using different paths.
    resources = Java::ResourcesTask.define_task("test:resources")
    project.path_to("src/test/resources").tap { |dir| resources.from dir if File.exist?(dir) }
    # Similar to the regular compile task but using different paths.
    compile = Java::CompileTask.define_task("test:compile"=>[project.compile, task("test:prepare"), project.test.resources])
    project.path_to("src/test/java").tap { |dir| compile.from dir if File.exist?(dir) }
    compile.into project.path_to(:target, "test-classes")
    resources.filter.into compile.target
    project.test.enhance [compile]
    # Define the JUnit task here, otherwise we get a normal task.
    Java::JUnitTask.define_task("test:junit")
    # Define these tasks once, otherwise we may get a namespace error.
    project.test.setup ; project.test.teardown

    project.enhance do |project|
      # Copy the regular compile classpath over, and also include the generated classes, both of which
      # can be used in the test cases. And don't forget the classpath required by the test framework (e.g. JUnit).
      project.test.with project.compile.classpath, project.compile.target, project.test.requires
      project.clean do
        verbose(false) do
          rm_rf project.test.compile.target.to_s
          rm_rf project.test.report_to.to_s
        end
      end
    end
  end


  class Options

    # Runs test cases after the build when true (default). This forces test cases to execute
    # after the build, including when running build related tasks like install, deploy and release.
    #
    # Set to false to not run any test cases. Set to :all to run all test cases, ignoring failures.
    #
    # This option is set from the environment variable "test", so you can also do:

    # Returns the test option (environment variable TEST). Possible values are:
    # * :false -- Do not run any test cases (also accepts "no" and "skip").
    # * :true -- Run all test cases, stop on failure (default if not set).
    # * :all -- Run all test cases, ignore failures.
    def test()
      case value = ENV["TEST"] || ENV["test"]
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
      ENV["test"] = nil
      ENV["TEST"] = flag.to_s
    end

  end


  desc "Run all test cases"
  task("test") { TestTask.run_local_tests false }

  # This rule takes a suffix and runs that test case in the current project. For example;
  #   buildr test:MyTest
  # will run the test case class com.example.MyTest, if found in the current project.
  #
  # If you want to run multiple test cases, separate tham with a comma. You can also use glob
  # (* and ?) patterns to match multiple tests, e.g. com.example.* to run all test cases in
  # a given package. If you don't specify a glob pattern, asterisks are added for you.
  rule /^test:.*$/ do |task|
    TestTask.only_run task.name.scan(/test:(.*)/)[0][0].split(",")
    task("test").invoke
  end

  task "build" do |task|
    # Make sure this happens as the last action on the build, so all other enhancements
    # are made to run before starting the test cases.
    task.enhance do
      task("test").invoke unless Buildr.options.test == false
    end
  end


  # The integration tests task. Buildr has one such task (see Buildr#integration) that runs
  # all tests marked with :integration=>true, and has a setup/teardown tasks separate from
  # the unit tests.
  class IntegrationTestsTask < Rake::Task

    def initialize(*args) #:nodoc:
      super
      task "#{name}-setup"
      task "#{name}-teardown"
      enhance { puts "Running integration tests..."  if verbose }
    end

    def execute() #:nodoc:
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
      Rake::Task["rake:integration-setup"].enhance prereqs, &block
    end

    # :call-seq:
    #   teardown(*prereqs) => task
    #   teardown(*prereqs) { |task| .. } => task
    #
    # Returns the teardown task. The teardown task is executed after running the integration tests.
    def teardown(*prereqs, &block)
      Rake::Task["rake:integration-teardown"].enhance prereqs, &block
    end

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
    Rake::Task["rake:integration"].enhance deps, &block
  end

  IntegrationTestsTask.define_task("integration") { TestTask.run_local_tests true }

  # Similar to test:[pattern] but for integration tests.
  rule /^integration:.*$/ do |task|
    TestTask.only_run task.name.scan(/integration:(.*)/)[0][0].split(",")
    task("integration").invoke
  end

  # Anything that comes after local packaging (install, deploy) executes the integration tests,
  # which do not conflict with integration invoking the project's own packaging (package=>
  # integration=>foo:package is not circular, just confusing to debug.)
  task "package" do |task|
    integration.invoke if Buildr.options.test && Rake.application.original_dir == Dir.pwd
  end


  task("help") do
    puts
    puts "To run a full build without running any test cases:"
    puts "  buildr test=no"
    puts "To run specific test case:"
    puts "  buildr test:MyTest"
    puts "To run integration tests:"
    puts "  buildr integration"
  end

end
