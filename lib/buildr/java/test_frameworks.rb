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


require 'buildr/core/build'
require 'buildr/core/compile'
require 'buildr/java/ant'

module Buildr

  class TestFramework
    module JavaTest

      # Add buildr utilities (JavaTestFilter) to classpath
      Java.classpath << File.join(File.dirname(__FILE__))

      def self.included(mod)
        super
        mod.extend ClassMethods
      end

      private
      # :call-seq:
      #     filter_classes(dependencies, criteria)
      # 
      # Return a list of classnames that match the given criteria. 
      # The criteria parameter is a hash that must contain at least one of:
      #
      # * :class_names -- List of patterns to match against class name
      # * :interfaces -- List of java interfaces or java classes
      # * :class_annotations -- List of annotations on class level
      # * :method_annotations -- List of annotations on method level
      #
      def filter_classes(dependencies, criteria = {})
        return [] unless task.compile.target
        target = task.compile.target.to_s
        candidates = Dir["#{target}/**/*.class"].
          map { |file| Util.relative_path(file, target).ext('').gsub(File::SEPARATOR, '.') }.
          reject { |name| name =~ /\$/ }
        result = []
        if criteria[:class_names]
          result.concat candidates.select { |name| criteria[:class_names].flatten.any? { |pat| pat === name } }
        end
        begin
          Java.load
          filter = Java.org.apache.buildr.JavaTestFilter.new(dependencies.to_java(Java.java.lang.String))
          if criteria[:interfaces]
            filter.add_interfaces(criteria[:interfaces].to_java(Java.java.lang.String)) 
          end
          if criteria[:class_annotations]
            filter.add_class_annotations(criteria[:class_annotations].to_java(Java.java.lang.String))
          end
          if criteria[:method_annotations]
            filter.add_method_annotations(criteria[:method_annotations].to_java(Java.java.lang.String))
          end
          result.concat filter.filter(candidates.to_java(Java.java.lang.String)).map(&:to_s)
        rescue =>ex
          puts "#{ex.class}: #{ex.message}" if verbose
          raise
        end
        result.uniq
      end
      
      module ClassMethods
        def applies_to?(project) #:nodoc:
          project.test.compile.language == :java
        end        
      end
      
    end
  end

  # JMock is available when using JUnit and TestNG, JBehave.
  module JMock
    # JMock version.
    VERSION = '1.2.0' unless const_defined?('VERSION')
    # JMock specification.
    REQUIRES = ["jmock:jmock:jar:#{VERSION}"]
  end


  # JUnit test framework, the default test framework for Java tests.
  #
  # Support the following options:
  # * :fork        -- If true/:once (default), fork for each test class.  If :each, fork for each individual
  #                   test case.  If false, run all tests in the same VM (fast, but dangerous).
  # * :clonevm     -- If true clone the VM each time it is forked.
  # * :properties  -- Hash of system properties available to the test case.
  # * :environment -- Hash of environment variables available to the test case.
  # * :java_args   -- Arguments passed as is to the JVM.
  class JUnit < TestFramework::Base

    # Used by the junit:report task. Access through JUnit#report if you want to set various
    # options for that task, for example:
    #   JUnit.report.frames = false
    class Report

      # Ant-Trax required for running the JUnitReport task.
      Java.classpath << "org.apache.ant:ant-trax:jar:#{Ant::VERSION}"

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

    # JUnit version number.
    VERSION = '4.3.1' unless const_defined?('VERSION')
    
    REQUIRES = ["junit:junit:jar:#{VERSION}"] + JMock::REQUIRES

    # Ant-JUnit requires for JUnit and JUnit reports tasks.
    Java.classpath << "org.apache.ant:ant-junit:jar:#{Ant::VERSION}"

    include TestFramework::JavaTest
    
    def tests(dependencies) #:nodoc:
      filter_classes(dependencies, 
                     :interfaces => %w{junit.framework.TestCase},
                     :class_annotations => %w{org.junit.runner.RunWith},
                     :method_annotations => %w{org.junit.Test})
    end

    def run(tests, dependencies) #:nodoc:
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
        mkpath task.report_to.to_s
        ant.junit forking.merge(:clonevm=>options[:clonevm] || false, :dir=>task.send(:project).path_to) do
          ant.classpath :path=>dependencies.join(File::PATH_SEPARATOR)
          (options[:properties] || []).each { |key, value| ant.sysproperty :key=>key, :value=>value }
          (options[:environment] || []).each { |key, value| ant.env :key=>key, :value=>value }
          Array(options[:java_args]).each { |value| ant.jvmarg :value=>value }
          ant.formatter :type=>'plain'
          ant.formatter :type=>'plain', :usefile=>false # log test
          ant.formatter :type=>'xml'
          ant.batchtest :todir=>task.report_to.to_s, :failureproperty=>'failed' do
            ant.fileset :dir=>task.compile.target.to_s do
              tests.each { |test| ant.include :name=>File.join(*test.split('.')).ext('class') }
            end
          end
        end
        return tests unless ant.project.getProperty('failed')
      end
      # But Ant doesn't tell us what went kaput, so we'll have to parse the test files.
      tests.inject([]) do |passed, test|
        report_file = File.join(task.report_to.to_s, "TEST-#{test}.txt")
        if File.exist?(report_file)
          report = File.read(report_file)
          # The second line (if exists) is the status line and we scan it for its values.
          status = (report.split("\n")[1] || '').scan(/(run|failures|errors):\s*(\d+)/i).
            inject(Hash.new(0)) { |hash, pair| hash[pair[0].downcase.to_sym] = pair[1].to_i ; hash }
          passed << test if status[:failures] == 0 && status[:errors] == 0
        end
        passed
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


  # TestNG test framework.  To use in your project:
  #   test.using :testng
  #
  # Support the following options:
  # * :properties -- Hash of properties passed to the test suite.
  # * :java_args -- Arguments passed to the JVM.
  class TestNG < TestFramework::Base

    # TestNG version number.
    VERSION = '5.5' unless const_defined?('VERSION')
    # TestNG specification.
    REQUIRES = ["org.testng:testng:jar:jdk15:#{VERSION}"] + JMock::REQUIRES

    include TestFramework::JavaTest

    def tests(dependencies) #:nodoc:
      filter_classes(dependencies, 
                     :class_annotations => %w{org.testng.annotations.Test},
                     :method_annotations => %w{org.testng.annotations.Test})
    end

    def run(tests, dependencies) #:nodoc:
      cmd_args = [ 'org.testng.TestNG', '-sourcedir', task.compile.sources.join(';'), '-suitename', task.send(:project).name ]
      cmd_args << '-d' << task.report_to.to_s
      cmd_options = { :properties=>options[:properties], :java_args=>options[:java_args],
                      :classpath=>dependencies }
      tests.inject([]) do |passed, test|
        begin
          Java::Commands.java cmd_args, '-testclass', test, cmd_options.merge(:name=>test)
          passed << test
        rescue
          passed
        end
      end
    end

  end

end


Buildr::TestFramework << Buildr::JUnit
Buildr::TestFramework << Buildr::TestNG

# Backward compatibility crap.
Buildr::JUnit::JUNIT_REQUIRES = Buildr::JUnit::REQUIRES
Buildr::TestNG::TestNG_REQUIRES = Buildr::TestNG::REQUIRES
Java::JUnit = Buildr::JUnit
Java::TestNG = Buildr::TestNG
