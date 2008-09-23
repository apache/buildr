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
require 'buildr/java/tests'

module Buildr

  # Mixin for test frameworks using src/spec/{lang}
  class TestFramework::JavaBDD < TestFramework::Java #:nodoc:

    class << self
      attr_reader :lang, :bdd_dir
    end
    attr_accessor :lang, :bdd_dir

    def initialize(task, options)
      self.bdd_dir = self.class.bdd_dir
      project = task.project
      project.task('test:compile').tap do |comp| 
        comp.send :associate_with, project, bdd_dir
        self.lang = comp.language || self.class.lang
      end
      project.task('test:resources').tap do |res|
        res.send :associate_with, project, bdd_dir
        res.filter.clear
        project.path_to(:source, bdd_dir, :resources).tap { |dir| res.from dir if File.exist?(dir) }
      end
      super
    end
    
  end

  module TestFramework::JRubyBased

    VERSION = '1.1.4' unless const_defined?('VERSION')

    class << self
      def version
        Buildr.settings.build['jruby'] || VERSION
      end
      
      def dependencies
        ["org.jruby:jruby-complete:jar:#{version}"]
      end

      def included(mod)
        mod.extend ClassMethods
        super
      end
    end

    module ClassMethods
      def dependencies
        super + (RUBY_PLATFORM[/java/] ? [] : JRubyBased.dependencies)
      end
    end

    def jruby_home
      @jruby_home ||= RUBY_PLATFORM =~ /java/ ? Config::CONFIG['prefix'] : 
        ( ENV['JRUBY_HOME'] || File.expand_path("~/.jruby") )
    end

    def jruby(*args)
      java_args = ["org.jruby.Main", *args]
      java_args << {} unless Hash === args.last
      cmd_options = java_args.last
      project = cmd_options.delete(:project)
      cmd_options[:java_args] ||= []
      cmd_options[:java_args] << "-Xmx512m" unless cmd_options[:java_args].detect {|a| a =~ /^-Xmx/}
      cmd_options[:properties] ||= {}
      cmd_options[:properties]['jruby.home'] = jruby_home
      Java::Commands.java(*java_args)
    end

    def new_runtime(cfg = {})
      config = Java.org.jruby.RubyInstanceConfig.new
      cfg.each_pair do |name, value|
        config.send("#{name}=", value)
      end
      yield config if block_given?
      Java.org.jruby.Ruby.newInstance config
    end
    
  end
  
  class RSpec < TestFramework::JavaBDD
    @lang = :ruby
    @bdd_dir = :spec    

    include TestFramework::JRubyBased
  
    TESTS_PATTERN = [ /_spec.rb$/ ]
    OPTIONS = [:properties, :java_args]

    def self.applies_to?(project) #:nodoc:
      !Dir[project.path_to(:source, bdd_dir, lang, '**/*_spec.rb')].empty?
    end

    def tests(dependencies) #:nodoc:
      Dir[task.project.path_to(:source, bdd_dir, lang, '**/*_spec.rb')].
        select do |name| 
        selector = ENV['SPEC']
        selector.nil? || Regexp.new(selector) === name
      end
    end

    def run(tests, dependencies) #:nodoc:
      #jruby_home or fail "To use RSpec you must either run on JRuby or have JRUBY_HOME set"
      cmd_options = task.options.only(:properties, :java_args)
      #dependencies.push *Dir.glob(File.join(jruby_home, "lib/*.jar")) if RUBY_PLATFORM =~ /java/
      cmd_options.update :classpath => dependencies, :project => task.project

      report_dir = task.report_to.to_s
      FileUtils.rm_rf report_dir
      ENV['CI_REPORTS'] = report_dir

      jruby '-Ilib', '-S', 'spec', '--require', 'ci/reporter/rake/rspec_loader',
        '--format', 'CI::Reporter::RSpecDoc', tests, cmd_options.merge(:name => 'RSpec')
      tests
    end

  private
  
    def jruby_home
      @jruby_home ||= RUBY_PLATFORM =~ /java/ ? Config::CONFIG['prefix'] : ENV['JRUBY_HOME']
    end

    def jruby(*args)
      java_args = ['org.jruby.Main', *args]
      java_args << {} unless Hash === args.last
      cmd_options = java_args.last
      project = cmd_options.delete(:project)
      cmd_options[:java_args] ||= []
      cmd_options[:java_args] << '-Xmx512m' unless cmd_options[:java_args].detect {|a| a =~ /^-Xmx/}
      cmd_options[:properties] ||= {}
      cmd_options[:properties]['jruby.home'] = jruby_home
      Java::Commands.java(*java_args)
    end

  end

  # <a href="http://jtestr.codehaus.org/">JtestR</a> is a framework for BDD and TDD using JRuby and ruby tools.
  # To test your project with JtestR use:
  #   test.using :jtestr
  #
  #
  # Support the following options:
  # * :config -- path to JtestR config file. defaults to @spec/ruby/jtestr_config.rb@
  # * :output -- path to JtestR output dump. @false@ to supress output
  class JtestR < TestFramework::JavaBDD
    @lang = :ruby
    @bdd_dir = :spec    

    include TestFramework::JRubyBased

    VERSION = '0.3.1' unless const_defined?('VERSION')
    JTESTR_ARTIFACT = "org.jtestr:jtestr:jar:#{VERSION}"
    
    # pattern for rspec stories
    STORY_PATTERN    = /_(steps|story)\.rb$/
    # pattern for test_unit files
    TESTUNIT_PATTERN = /(_test|Test)\.rb$|(tc|ts)[^\\\/]+\.rb$/
    # pattern for test files using http://expectations.rubyforge.org/
    EXPECT_PATTERN   = /_expect\.rb$/

    TESTS_PATTERN = [STORY_PATTERN, TESTUNIT_PATTERN, EXPECT_PATTERN] + RSpec::TESTS_PATTERN

    class << self

      def version
        Buildr.settings.build['jtestr'] || VERSION
      end

      def dependencies
        @dependencies ||= Array(super) + ["org.jtestr:jtestr:jar:#{version}"] +
          JUnit.dependencies + TestNG.dependencies
      end
    
      def applies_to?(project) #:nodoc:
        File.exist?(project.path_to(:source, bdd_dir, lang, 'jtestr_config.rb')) ||
          Dir[project.path_to(:source, bdd_dir, lang, '**/*.rb')].any? { |f| TESTS_PATTERN.any? { |r| r === f } } ||
          JUnit.applies_to?(project) || TestNG.applies_to?(project)
      end

    private
      def const_missing(const)
        return super unless const == :REQUIRES # TODO: remove in 1.5
        Buildr.application.deprecated "Please use JtestR.dependencies/.version instead of JtestR::REQUIRES/VERSION"
        dependencies
      end

    end

    def initialize(task, options) #:nodoc:
      super
      [:test, :spec].each do |usage|
        java_tests = task.project.path_to(:source, usage, :java)
        task.compile.from java_tests if File.directory?(java_tests)
        resources = task.project.path_to(:source, usage, :resources)
        task.resources.from resources if File.directory?(resources)
      end
    end

    def user_config
      options[:config] || task.project.path_to(:source, bdd_dir, lang, 'jtestr_config.rb')
    end

    def tests(dependencies) #:nodoc:
      dependencies += [task.compile.target.to_s]
      types = { :story => STORY_PATTERN, :rspec => RSpec::TESTS_PATTERN,
                :testunit => TESTUNIT_PATTERN, :expect => EXPECT_PATTERN }
      tests = types.keys.inject({}) { |h, k| h[k] = []; h }
      tests[:junit] = JUnit.new(task, {}).tests(dependencies)
      tests[:testng] = TestNG.new(task, {}).tests(dependencies)
      Dir[task.project.path_to(:source, bdd_dir, lang, '**/*.rb')].each do |rb|
        type = types.find { |k, v| Array(v).any? { |r| r === rb } }
        tests[type.first] << rb if type
      end
      @jtestr_tests = tests
      tests = tests.values.flatten
      tests << nil if File.exist?(user_config)
      tests
    end

    def run(tests, dependencies) #:nodoc:
      dependencies += [task.compile.target.to_s]
      
      yaml_report = File.join(task.report_to.to_s, 'result.yaml')
      spec_dir = task.project.path_to(:source, :spec, :ruby)

      runner_file = task.project.path_to(:target, :spec, 'jtestr_runner.rb')
      runner_erb = File.join(File.dirname(__FILE__), 'jtestr_runner.rb.erb')
      runner = Filter::Mapper.new(:erb, binding).result(File.read(runner_erb))
      Buildr.write runner_file, runner

      if /java/ === RUBY_PLATFORM
        runtime = new_runtime :current_directory => runner_file.pathmap('%d')
        runtime.getLoadService.require runner_file
      else
        cmd_options = task.options.only(:properties, :java_args)
        cmd_options.update(:classpath => dependencies, :project => task.project)
        jruby runner_file, cmd_options.merge(:name => 'JtestR')
      end

      report = YAML::load(File.read(yaml_report))
      raise (Array(report[:error][:message]) + report[:error][:backtrace]).join("\n") if report[:error]
      report[:success]
    end
    
  end

  
  # JBehave is a Java BDD framework. To use in your project:
  #   test.using :jbehave
  # 
  # This framework will search in your project for:
  #   src/spec/java/**/*Behaviour.java
  # 
  # JMock libraries are included on runtime.
  #
  # Support the following options:
  # * :properties -- Hash of properties to the test suite
  # * :java_args -- Arguments passed to the JVM
  class JBehave < TestFramework::JavaBDD
    @lang = :java
    @bdd_dir = :spec

    VERSION = "1.0.1" unless const_defined?('VERSION')
    TESTS_PATTERN = [ /Behaviou?r$/ ] #:nodoc:
    
    class << self
      def version
        Buildr.settings.build['jbehave'] || VERSION
      end

      def dependencies
        @dependencies ||= ["org.jbehave:jbehave:jar:#{version}", "cglib:cglib-full:jar:2.0.2"] +
          JMock.dependencies + JUnit.dependencies
      end

      def applies_to?(project) #:nodoc:
        %w{
          **/*Behaviour.java **/*Behavior.java
        }.any? { |glob| !Dir[project.path_to(:source, bdd_dir, lang, glob)].empty? }
      end

    private
      def const_missing(const)
        return super unless const == :REQUIRES # TODO: remove in 1.5
        Buildr.application.deprecated "Please use JBehave.dependencies/.version instead of JBehave::REQUIRES/VERSION"
        dependencies
      end
    end

    def tests(dependencies) #:nodoc:
      filter_classes(dependencies, :class_names => TESTS_PATTERN,
                     :interfaces => %w{ org.jbehave.core.behaviour.Behaviours })
    end
    
    def run(tests, dependencies) #:nodoc:
      cmd_args = ['org.jbehave.core.BehaviourRunner']
      cmd_options = { :properties=>options[:properties], :java_args=>options[:java_args], :classpath=>dependencies }
      tests.inject([]) do |passed, test|
        begin
          Java::Commands.java cmd_args, test, cmd_options
          passed << test
        rescue
          passed
        end
      end
    end
    
  end

end

Buildr::TestFramework << Buildr::RSpec
Buildr::TestFramework << Buildr::JtestR
Buildr::TestFramework << Buildr::JBehave
