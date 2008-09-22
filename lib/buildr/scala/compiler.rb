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

require 'buildr/core/project'
require 'buildr/core/common'
require 'buildr/core/compile'
require 'buildr/packaging'


module Buildr::Scala
    
  # Scalac compiler:
  #   compile.using(:scalac)
  # Used by default if .scala files are found in the src/main/scala directory (or src/test/scala)
  # and sets the target directory to target/classes (or target/test/classes).
  #
  # Accepts the following options:
  # * :warnings    -- Generate warnings if true (opposite of -nowarn).
  # * :deprecation -- Output source locations where deprecated APIs are used.
  # * :optimise    -- Generates faster bytecode by applying optimisations to the program.
  # * :target      -- Class file compatibility with specified release.
  # * :debug       -- Generate debugging info.
  # * :other       -- Array of options to pass to the Scalac compiler as is, e.g. -Xprint-types
  class Scalac < Buildr::Compiler::Base
    class << self
      def scala_home
        @home ||= ENV['SCALA_HOME']
      end

      def dependencies
        [ 'scala-library.jar', 'scala-compiler.jar'].map { |jar| File.expand_path("lib/#{jar}", scala_home) }
      end

      def use_fsc
        ENV["USE_FSC"] =~ /^(yes|on|true)$/i
      end
    end

    OPTIONS = [:warnings, :deprecation, :optimise, :target, :debug, :other]
    Java.classpath << dependencies

    specify :language=>:scala, :target=>'classes', :target_ext=>'class', :packaging=>:jar

    def initialize(project, options) #:nodoc:
      super
      options[:debug] = Buildr.options.debug if options[:debug].nil?
      options[:warnings] = verbose if options[:warnings].nil?
      options[:deprecation] ||= false
      options[:optimise] ||= false
    end

    def compile(sources, target, dependencies) #:nodoc:
      check_options options, OPTIONS

      cmd_args = []
      cmd_args << '-classpath' << (dependencies + Scalac.dependencies).join(File::PATH_SEPARATOR)
      source_paths = sources.select { |source| File.directory?(source) }
      cmd_args << '-sourcepath' << source_paths.join(File::PATH_SEPARATOR) unless source_paths.empty?
      cmd_args << '-d' << File.expand_path(target)
      cmd_args += scalac_args
      cmd_args += files_from_sources(sources)

      unless Buildr.application.options.dryrun
        Scalac.scala_home or fail 'Are we forgetting something? SCALA_HOME not set.'
        trace((['scalac'] + cmd_args).join(' '))
        if Scalac.use_fsc
          system(([File.expand_path('bin/fsc', Scalac.scala_home)] + cmd_args).join(' ')) or
            fail 'Failed to compile, see errors above'
        else
          Java.load
          Java.scala.tools.nsc.Main.process(cmd_args.to_java(Java.java.lang.String))
          fail 'Failed to compile, see errors above' if Java.scala.tools.nsc.Main.reporter.hasErrors
        end
      end
    end

  private

    # Returns Scalac command line arguments from the set of options.
    def scalac_args #:nodoc:
      args = []
      args << "-nowarn" unless options[:warnings]
      args << "-verbose" if Buildr.application.options.trace
      args << "-g" if options[:debug]
      args << "-deprecation" if options[:deprecation]
      args << "-optimise" if options[:optimise]
      args << "-target:jvm-" + options[:target].to_s if options[:target]
      args + Array(options[:other])
    end

  end
    
end

# Scala compiler comes first, ahead of Javac, this allows it to pick
# projects that mix Scala and Java code by spotting Scala code first.
Buildr::Compiler.compilers.unshift Buildr::Scala::Scalac