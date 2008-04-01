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


require 'buildr/java/test_frameworks'


module Buildr

  # Mixin for test frameworks using src/spec/{lang}
  module TestFramework::JavaBDD #:nodoc:
    
    class << self
      def included(mod)
        mod.module_eval do
          include TestFramework::JavaTest
          include ClassMethods
        end
        mod.extend ClassMethods
        mod.bdd_dir = :spec
        mod.lang = :java
        super
      end
    end

    module ClassMethods
      attr_accessor :lang, :bdd_dir
    end

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
        project.path_to(:source, bdd_dir, :resources).tap { |dir| resources.from dir if File.exist?(dir) }
      end
      super
    end
  end
  
  class RSpec < TestFramework::Base
    include TestFramework::JavaBDD
    self.lang = :ruby

    REQUIRES = ['org.jruby:jruby-complete:jar:1.1RC2']
    TESTS_PATTERN = [ /_spec.rb$/ ]
    OPTIONS = [:properties, :java_args]

    def self.applies_to?(project) #:nodoc:
      !Dir[project.path_to(:source, bdd_dir, lang, '**/*_spec.rb')].empty?
    end

    def tests(dependencies) #:nodoc:
      if ENV['SPEC']
        FileList[Env['SPEC']]
      else
        Dir[task.project.path_to(:source, bdd_dir, "ruby/**/*_spec.rb")]
      end
    end

    def run(tests, dependencies) #:nodoc:
      tests # TODO
    end
  end

  class JtestR < TestFramework::Base
    include TestFramework::JavaBDD
    self.lang = :ruby
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
  class JBehave < TestFramework::Base
    include TestFramework::JavaBDD

    VERSION = "1.0.1" unless const_defined?('VERSION')
    REQUIRES = ["org.jbehave:jbehave:jar:#{VERSION}",
                "jmock:jmock-cglib:jar:#{JMock::VERSION}",
                "cglib:cglib-full:jar:2.0.2",
               ] + JUnit::REQUIRES
    TESTS_PATTERN = [ /Behaviou?r$/ ]

    def self.applies_to?(project) #:nodoc:
      %w{
        **/*Behaviour.java **/*Behavior.java
      }.any? { |glob| !Dir[project.path_to(:source, bdd_dir, lang, glob)].empty? }
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

  # EasyB is a Groovy based BDD framework.
  # To use in your project:
  #
  #   test.using :easyb
  # 
  # This framework will search in your project for:
  #   src/spec/groovy/**/*Story.groovy
  #   src/spec/groovy/**/*Behavior.groovy
  #
  # Support the following options:
  # * :format -- Report format :txt or :xml, default is :txt
  # * :properties -- Hash of properties passed to the test suite.
  # * :java_args -- Arguments passed to the JVM.
  class EasyB < TestFramework::Base
    include TestFramework::JavaBDD
    self.lang = :groovy

    VERSION = "0.7" unless const_defined?(:VERSION)
    REQUIRES = ["org.easyb:easyb:jar:#{VERSION}",
                'org.codehaus.groovy:groovy:jar:1.5.3',
                'asm:asm:jar:2.2.3',
                'commons-cli:commons-cli:jar:1.0',
                'antlr:antlr:jar:2.7.7']
    TESTS_PATTERN = [ /(Story|Behavior).groovy$/ ]
    OPTIONS = [:format, :properties, :java_args]

    def self.applies_to?(project) #:nodoc:
      %w{
        **/*Behaviour.groovy **/*Behavior.groovy **/*Story.groovy
      }.any? { |glob| !Dir[project.path_to(:source, bdd_dir, lang, glob)].empty? }
    end
   
    def tests(dependencies) #:nodoc:
      Dir[task.project.path_to(:source, bdd_dir, "groovy/**/*.groovy")].
        select { |name| TESTS_PATTERN.any? { |pat| pat === name } }
    end

    def run(tests, dependencies) #:nodoc:
      options = { :format => :txt }.merge(self.options).only(*OPTIONS)
      
      if :txt == options[:format]
        easyb_format, ext = 'txtstory', '.txt'
      elsif :xml == options[:format]
        easyb_format, ext = 'xmlbehavior', '.xml'
      else
        raise "Invalid format #{options[:format]} expected one of :txt :xml"
      end
      
      cmd_args = [ 'org.disco.easyb.SpecificationRunner' ]
      cmd_options = { :properties => options[:properties],
                      :java_args => options[:java_args],
                      :classpath => dependencies }

      tests.inject([]) do |passed, test|
        name = test.sub(/.*?groovy[\/\\]/, '').pathmap('%X')
        report = File.join(task.report_to.to_s, name + ext)
        mkpath report.pathmap('%d'), :verbose => false
        begin
          Java::Commands.java cmd_args,
             "-#{easyb_format}", report,
             test, cmd_options.merge(:name => name)
        rescue => e
          passed
        else
          passed << test
        end
      end
    end
    
  end # EasyB

end

Buildr::TestFramework << Buildr::RSpec
Buildr::TestFramework << Buildr::JtestR
Buildr::TestFramework << Buildr::JBehave
Buildr::TestFramework << Buildr::EasyB
