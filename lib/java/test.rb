require 'core/build'
require 'java/compile'
require 'java/ant'
require 'core/help'


module Buildr
  module Java

    module JMock
      # JMock version..
      JMOCK_VERSION = '1.2.0'
      # JMock specification.
      JMOCK_REQUIRES = ["jmock:jmock:jar:#{JMOCK_VERSION}"]
    end

    # The JUnit test framework. This is the default test framework, but you can force it by
    # adding the following to your project:
    #   test.using :testng
    #
    # You can use the report method to control the junit:report task.
    module JUnit

      include JMock

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

        def initialize
          @params = {}
          @frames = true
          @target = 'reports/junit'
        end

        # :call-seq:
        #   generate(projects, target?)
        #
        # Generates a JUnit report for these projects (must run JUnit tests first) into the
        # target directory. You can specify a target, or let it pick the default one from the
        # target attribute.
        def generate(projects, target = @target.to_s)
          html_in = File.join(target, 'html')
          rm_rf html_in ; mkpath html_in
          
          Buildr.ant('junit-report') do |ant|
            ant.junitreport :todir=>target do
              projects.select { |project| project.test.framework == :junit }.
                map { |project| project.test.report_to.to_s }.select { |path| File.exist?(path) }.
                each { |path| ant.fileset(:dir=>path) { ant.include :name=>'TEST-*.xml' }  }
              options = { :format=>frames ? 'frames' : 'noframes' }
              options[:styledir] = style_dir if style_dir
              ant.report options.merge(:todir=>html_in) do
                params.each { |key, value| ant.param :name=>key, :expression=>value }
              end
            end
          end
        end

      end

      # JUnit version number.
      JUNIT_VERSION = '4.3.1'
      # JUnit specification.
      JUNIT_REQUIRES = ["junit:junit:jar:#{JUNIT_VERSION}"] + JMOCK_REQUIRES
      # Pattern for selecting JUnit test classes. Regardless of include/exclude patterns, only classes
      # that match this pattern are used.
      JUNIT_TESTS_PATTERN = [ 'Test*.class', '*Test.class' ]

      # Ant-JUnit requires for JUnit and JUnit reports tasks.
      Java.wrapper.setup { |jw| jw.classpath << "org.apache.ant:ant-junit:jar:#{Ant::VERSION}" }

      class << self

        # :call-seq:
        #    report()
        #
        # Returns the Report object used by the junit:report task. You can use this object to set
        # various options that affect your report, for example:
        #   JUnit.report.frames = false
        #   JUnit.report.params['title'] = 'My App'
        def report
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
        Buildr.ant('junit') do |ant|
          case options[:fork]
          when false
            forking = {}
          when :each
            forking = { :fork=>true, :forkmode=>'perTest' }
          when true, :once
            forking = { :fork=>true, :forkmode=>'once' }
          else
            fail 'Option fork must be :once, :each or false.'
          end
          ant.junit forking.merge(:clonevm=>options[:clonevm] || false, :dir=>@project.path_to) do
            ant.classpath :path=>args[:dependencies].map(&:to_s).each { |path| file(path).invoke }.join(File::PATH_SEPARATOR)
            args[:properties].each { |key, value| ant.sysproperty :key=>key, :value=>value }
            args[:environment].each { |key, value| ant.env :key=>key, :value=>value }
            java_args = args[:java_args]
            java_args = java_args.split(' ') if String === java_args
            java_args.each { |value| ant.jvmarg :value=>value } if java_args
            ant.formatter :type=>'plain'
            ant.formatter :type=>'xml'
            ant.formatter :type=>'plain', :usefile=>false # log test
            ant.formatter :type=>'xml'
            ant.batchtest :todir=>report_to.to_s, :failureproperty=>'failed' do
              ant.fileset :dir=>compile.target.to_s do
                args[:files].each { |cls| ant.include :name=>cls.gsub('.', '/').ext('class') }
              end
            end
          end
          return [] unless ant.project.getProperty('failed')
        end
        # But Ant doesn't tell us what went kaput, so we'll have to parse the test files.
        args[:files].inject([]) do |failed, name|
          if report = File.read(File.join(report_to.to_s, "TEST-#{name}.txt")) rescue nil
            # The second line (if exists) is the status line and we scan it for its values.
            status = (report.split("\n")[1] || '').scan(/(run|failures|errors):\s*(\d+)/i).
              inject(Hash.new(0)) { |hash, pair| hash[pair[0].downcase.to_sym] = pair[1].to_i ; hash }
            failed << name if status[:failures] > 0 || status[:errors] > 0
          end
          failed
        end
      end

      namespace 'junit' do
        desc "Generate JUnit tests report in #{report.target}"
        task('report') do |task|
          report.generate Project.projects
          puts "Generated JUnit tests report in #{report.target}"
        end
      end

      task('clean') { rm_rf report.target.to_s }

    end


    # The TestNG test framework. Use by adding the following to your project:
    #   test.using :testng
    module TestNG

      include JMock

      # TestNG version number.
      TESTNG_VERSION = '5.5'
      # TestNG specification.
      TESTNG_REQUIRES = ["org.testng:testng:jar:jdk15:#{TESTNG_VERSION}"] + JMOCK_REQUIRES
      # Pattern for selecting TestNG test classes. Regardless of include/exclude patterns, only classes
      # that match this pattern are used.
      TESTNG_TESTS_PATTERN = [ 'Test*.class', '*Test.class', '*TestCase.class' ]

      class << self

        def included(mod)
          mod::TEST_FRAMEWORKS << :testng
        end
        private :included

      end

    private

      def testng_run(args)
        cmd_args = [ 'org.testng.TestNG', '-sourcedir', compile.sources.join(';'), '-suitename', @project.name ]
        cmd_args << '-d' << report_to.to_s
        cmd_options = args.only(:properties, :java_args)
        cmd_options[:classpath] = args[:dependencies]
        args[:files].inject([]) do |failed, test|
          begin
            Buildr.java cmd_args, '-testclass', test, cmd_options.merge(:name=>test)
            failed
          rescue
            failed << test
          end
        end
      end

    end

  end

  class TestTask
    include Java::JUnit
    include Java::TestNG
  end

end
