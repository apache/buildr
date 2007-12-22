require 'core/build'
require 'core/compile'
require 'java/ant'
require 'core/help'


module Buildr
  class TestFramework

    module JMock
      # JMock version..
      JMOCK_VERSION = '1.2.0'
      # JMock specification.
      JMOCK_REQUIRES = ["jmock:jmock:jar:#{JMOCK_VERSION}"]
    end


    class JUnit < Base

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

      end


      # Ant-JUnit requires for JUnit and JUnit reports tasks.
      ::Buildr::Java.wrapper.setup { |jw| jw.classpath << "org.apache.ant:ant-junit:jar:#{Ant::VERSION}" }

      include JMock

      # JUnit version number.
      JUNIT_VERSION = '4.3.1'
      # JUnit specification.
      JUNIT_REQUIRES = ["junit:junit:jar:#{JUNIT_VERSION}"] + JMOCK_REQUIRES
      # Pattern for selecting JUnit test classes. Regardless of include/exclude patterns, only classes
      # that match this pattern are used.
      JUNIT_TESTS_PATTERN = [ 'Test*.class', '*Test.class' ]

      def initialize
        super :requires=>JUNIT_REQUIRES, :patterns=>JUNIT_TESTS_PATTERN
      end

      def files(path)
        # Ignore anonymous classes.
        super(path).reject { |name| name =~ /\$/ }
      end

      def run(files, task, dependencies)
        # Use Ant to execute the Junit tasks, gives us performance and reporting.
        Buildr.ant('junit') do |ant|
          case task.options[:fork]
          when false
            forking = {}
          when :each
            forking = { :fork=>true, :forkmode=>'perTest' }
          when true, :once
            forking = { :fork=>true, :forkmode=>'once' }
          else
            fail 'Option fork must be :once, :each or false.'
          end
          mkpath task.report_to.to_s
          ant.junit forking.merge(:clonevm=>task.options[:clonevm] || false, :dir=>task.send(:project).path_to) do
            ant.classpath :path=>dependencies.each { |path| file(path).invoke }.join(File::PATH_SEPARATOR)
            (task.options[:properties] || []).each { |key, value| ant.sysproperty :key=>key, :value=>value }
            (task.options[:environment] || []).each { |key, value| ant.env :key=>key, :value=>value }
            java_args = task.options[:java_args] || Buildr.options.java_args
            java_args = java_args.split(/\s+/) if String === java_args
            java_args.each { |value| ant.jvmarg :value=>value } if java_args
            ant.formatter :type=>'plain'
            ant.formatter :type=>'plain', :usefile=>false # log test
            ant.formatter :type=>'xml'
            ant.batchtest :todir=>task.report_to.to_s, :failureproperty=>'failed' do
              ant.fileset :dir=>task.compile.target.to_s do
                files.each { |file| ant.include :name=>file }
              end
            end
          end
          return [] unless ant.project.getProperty('failed')
        end
        # But Ant doesn't tell us what went kaput, so we'll have to parse the test files.
        files.inject([]) do |failed, file|
          test = file.ext('').gsub(File::SEPARATOR, '.')
          report_file = File.join(task.report_to.to_s, "TEST-#{test}.txt")
          if File.exist?(report_file)
            report = File.read(report_file)
            # The second line (if exists) is the status line and we scan it for its values.
            status = (report.split("\n")[1] || '').scan(/(run|failures|errors):\s*(\d+)/i).
              inject(Hash.new(0)) { |hash, pair| hash[pair[0].downcase.to_sym] = pair[1].to_i ; hash }
            failed << test if status[:failures] > 0 || status[:errors] > 0
          end
          failed
        end
      end

      namespace 'junit' do
        desc "Generate JUnit tests report in #{report.target}"
        task('report') do |task|
          report.generate Project.projects
          puts "Generated JUnit tests report in #{report.target}" if verbose
        end
      end

      task('clean') { rm_rf report.target.to_s }

    end

    TestFramework.add JUnit


    class TestNG < Base

      include JMock

      # TestNG version number.
      TESTNG_VERSION = '5.5'
      # TestNG specification.
      TESTNG_REQUIRES = ["org.testng:testng:jar:jdk15:#{TESTNG_VERSION}"] + JMOCK_REQUIRES
      # Pattern for selecting TestNG test classes. Regardless of include/exclude patterns, only classes
      # that match this pattern are used.
      TESTNG_TESTS_PATTERN = [ 'Test*.class', '*Test.class', '*TestCase.class' ]

      def initialize
        super :requires=>TESTNG_REQUIRES, :patterns=>TESTNG_TESTS_PATTERN
      end

      def files(path)
        # Ignore anonymous classes.
        super(path).reject { |name| name =~ /\$/ }
      end

      def run(files, task, dependencies)
        cmd_args = [ 'org.testng.TestNG', '-sourcedir', task.compile.sources.join(';'), '-suitename', task.send(:project).name ]
        cmd_args << '-d' << task.report_to.to_s
        cmd_options = { :properties=>task.options[:properties], :java_args=>task.options[:java_args],
                        :classpath=>dependencies }
        files.map { |file| file.ext('').gsub(File::SEPARATOR, '.') }.inject([]) do |failed, test|
          begin
            Buildr.java cmd_args, '-testclass', test, cmd_options.merge(:name=>test)
            failed
          rescue
            failed << test
          end
        end
      end

    end

    TestFramework.add TestNG

  end

end
