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
require 'buildr/java/bdd'
require 'buildr/scala/tests'

module Buildr::Scala

  # Specs is a Scala based BDD framework.
  # To use in your project:
  #
  #   test.using :specs
  #
  # This framework will search in your project for:
  #   src/spec/scala/**/*.scala
  class Specs < Buildr::TestFramework::JavaBDD
    @lang = :scala
    @bdd_dir = :spec

    VERSION = case
      when Buildr::Scala.version?("2.8.0")
        '1.6.5'
      when Buildr::Scala.version?("2.8.1")
        '1.6.8'
      else
        '1.6.8'
    end


    class << self
      def version
        custom = Buildr.settings.build['scala.specs']
        (custom =~ /:/) ? Buildr.artifact(custom).version : VERSION
      end

      def specs
        custom = Buildr.settings.build['scala.specs']
        [ (custom =~ /:/) ? custom : "org.scala-tools.testing:#{artifact}:jar:#{version}" ]
      end

      def artifact
        Buildr.settings.build['scala.specs.artifact'] || "specs_#{Buildr::Scala.version_without_build}"
      end

      def dependencies
        unless @dependencies
          super
          # Add utility classes (e.g. SpecsSingletonRunner) and other dependencies
          @dependencies |= [ File.join(File.dirname(__FILE__)) ] + specs +
                           Check.dependencies + JUnit.dependencies + Scalac.dependencies
        end
        @dependencies
      end

      def applies_to?(project)  #:nodoc:
        !Dir[project.path_to(:source, bdd_dir, lang, '**/*.scala')].empty?
      end

    private
      def const_missing(const)
        return super unless const == :REQUIRES # TODO: remove in 1.5
        Buildr.application.deprecated "Please use Scala::Specs.dependencies/.version instead of ScalaSpecs::REQUIRES/VERSION"
        dependencies
      end
    end

    def initialize(task, options) #:nodoc:
      super

      specs = task.project.path_to(:source, :spec, :scala)
      task.compile.from specs if File.directory?(specs)

      resources = task.project.path_to(:source, :spec, :resources)
      task.resources.from resources if File.directory?(resources)
    end

    def tests(dependencies)
      candidates = filter_classes(dependencies, :interfaces => ['org.specs.Specification'])

      Java.load   # Java is already loaded, but just in case

      filter = Java.org.apache.buildr.JavaTestFilter.new(dependencies.to_java(Java.java.lang.String))
      filter.add_fields ['MODULE$'].to_java(Java.java.lang.String)
      filter.filter(candidates.to_java(Java.java.lang.String)).map { |s| s[0..(s.size - 2)] }
    end

    def run(specs, dependencies)  #:nodoc:
      cmd_options = { :properties => options[:properties],
                      :java_args => options[:java_args],
                      :classpath => dependencies,
                      :name => false }

      runner = 'org.apache.buildr.SpecsSingletonRunner'
      specs.inject [] do |passed, spec|
        begin
          unless Util.win_os?
            Java::Commands.java(runner, task.compile.target.to_s, '-c', spec + '$', cmd_options)
          else
            Java::Commands.java(runner, task.compile.target.to_s, spec + '$', cmd_options)
          end
        rescue => e
          passed
        else
          passed << spec
        end
      end
    end
  end
end

# Backwards compatibility stuff.  Remove in 1.5.
module Buildr
  ScalaSpecs = Scala::Specs
end

Buildr::TestFramework << Buildr::Scala::Specs
