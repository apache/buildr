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

# The Kotlin Module
module Buildr::Kotlin
  DEFAULT_VERSION = '1.1.3-2'

  class << self

    def installed_version
      unless @installed_version
        @installed_version = if Kotlinc.installed?
          begin
            # try to read the value from the build.txt file
            version_str = File.read(File.expand_path('build.txt', Kotlinc.kotlin_home))

            if version_str
              md = version_str.match(/\d+\.\d[\d\.]*/) or
                fail "Unable to parse Kotlin version: #{version_str}"

              md[0].sub(/.$/, "") # remove trailing dot, if any
            end
          rescue => e
            warn "Unable to parse library.properties in $KOTLIN_HOME/build.txt: #{e}"
            nil
          end
        end
      end

      @installed_version
    end

    def version
      Buildr.settings.build['kotlin.version'] || installed_version || DEFAULT_VERSION
    end

    # check if version matches any of the given prefixes
    def version?(*v)
      v.any? { |v| version.index(v.to_s) == 0 }
    end

  end

  # Kotlin compiler:
  #   compile.using(:kotlin)
  # Used by default if .kt files are found in the src/main/kotlin directory (or src/test/kotlin)
  # and sets the target directory to target/classes (or target/test/classes).
  # Accepts the following options:
  # * :warnings    -- Issue warnings when compiling.  True when running in verbose mode.
  # * :debug       -- Generates bytecode with debugging information.  Set from the debug
  # environment variable/global option.
  # * :optimize    -- Optimize the byte code generation. False by default.
  # * :target      -- Bytecode compatibility.
  # * :noStdlib    -- Include the Kotlin runtime. False by default.
  # * :javac       -- Arguments for javac compiler.
  class Kotlinc < Buildr::Compiler::Base

    class << self
      def kotlin_home
        env_home = ENV['KOTLIN_HOME']

        @home ||= if !env_home.nil? && File.exists?(env_home + '/lib/kotlin-compiler.jar')
          env_home
        else
          nil
        end
      end

      def installed?
        !kotlin_home.nil?
      end

      def use_installed?
        if installed? && Buildr.settings.build['kotlin.version']
          Buildr.settings.build['kotlin.version'] == Kotlin.installed_version
        else
          Buildr.settings.build['kotlin.version'].nil? && installed?
        end
      end

      def dependencies
        kotlin_dependencies = if use_installed?
          %w(kotlin-stdlib kotlin-compiler).map { |s| File.expand_path("lib/#{s}.jar", kotlin_home) }
        else
          REQUIRES.artifacts.map(&:to_s)
        end
        # Add Java utilities (eg KotlinMessageCollector)
        kotlin_dependencies |= [ File.join(File.dirname(__FILE__)) ]
        (kotlin_dependencies).compact
      end

      def applies_to?(project, task) #:nodoc:
        paths = task.sources + [sources].flatten.map { |src| Array(project.path_to(:source, task.usage, src.to_sym)) }
        paths.flatten!

        # Just select if we find .kt files
        paths.any? { |path| !Dir["#{path}/**/*.kt"].empty? }
      end
    end

    # The kotlin compiler jars are added to classpath at load time,
    # if you want to customize artifact versions, you must set them on the
    #
    #      artifact_ns['Buildr::Compiler::Kotlinc'].library = '1.1.3-2'
    #
    # namespace before this file is required.  This is of course, only
    # if KOTLIN_HOME is not set or invalid.
    REQUIRES = ArtifactNamespace.for(self) do |ns|
      version = Buildr.settings.build['kotlin.version'] || DEFAULT_VERSION
      ns.compiler!     'org.jetbrains.kotlin:kotlin-compiler:jar:>=' + version
    end

    Javac = Buildr::Compiler::Javac

    OPTIONS = [:warnings, :optimize, :target, :debug, :noStdlib, :javac]

    # Lazy evaluation to allow change in buildfile
    Java.classpath << lambda { dependencies }

    specify :language=>:kotlin, :sources => [:kotlin, :java], :source_ext => [:kt, :java],
            :target=>'classes', :target_ext=>'class', :packaging=>:jar

    def initialize(project, options) #:nodoc:
      super
      # use common options also for javac

      options[:javac] ||= Buildr::Compiler::Javac::OPTIONS.inject({}) do |hash, option|
        hash[option] = options[option]
        hash
      end
      
      options[:debug] = Buildr.options.debug || trace?(:kotlinc) if options[:debug].nil?
      options[:warnings] = verbose if options[:warnings].nil?
      options[:optimize] = false if options[:optimize].nil?
      options[:noStdlib] = true if options[:noStdlib].nil?
      @java = Javac.new(project, options[:javac])
    end
    
    

    def compile(sources, target, dependencies) #:nodoc:
      check_options(options, OPTIONS)

      java_sources = java_sources(sources)

      unless Buildr.application.options.dryrun
        messageCollector = Java.org.apache.buildr.KotlinMessageCollector.new

        Java.load
        begin
          compiler = Java.org.jetbrains.kotlin.cli.jvm.K2JVMCompiler.new
          compilerArguments = kotlinc_args
          compilerArguments.destination = File.expand_path(target)
          compilerArguments.classpath = dependencies.join(File::PATH_SEPARATOR)
          sources.each do |source|
            compilerArguments.freeArgs.add(File.expand_path(source))
          end
          services = Buildr::Util.java_platform? ? Java.org.jetbrains.kotlin.config.Services::EMPTY : Java.org.jetbrains.kotlin.config.Services.EMPTY
          compiler.exec(messageCollector, services, compilerArguments)
        rescue => e
          fail "Kotlin compiler crashed:\n#{e.inspect}"
        end

        unless java_sources.empty?
          trace 'Compiling mixed Java/Kotlin sources'

          deps = dependencies + Kotlinc.dependencies + [ File.expand_path(target) ]
          @java.compile(java_sources, target, deps)
        end
      end
    end

  protected

    # :nodoc: see Compiler:Base
    def compile_map(sources, target)
      target_ext = self.class.target_ext
      ext_glob = Array(self.class.source_ext).join(',')
      sources.flatten.map{|f| File.expand_path(f)}.inject({}) do |map, source|
        sources = if File.directory?(source)
          FileList["#{source}/**/*.{#{ext_glob}}"].reject { |file| File.directory?(file) }
        else
          [source]
        end

        sources.each do |source|
          # try to extract package name from .java or .kt files
          if %w(.java .kt).include? File.extname(source)
            name = File.basename(source).split(".")[0]
            package = findFirst(source, /^\s*package\s+([^\s;]+)\s*;?\s*/)
            packages = count(source, /^\s*package\s+([^\s;]+)\s*;?\s*/)
            found = findFirst(source, /((class)|(object))\s+(#{name})Kt/)

            # if there's only one package statement and we know the target name, then we can depend
            # directly on a specific file, otherwise, we depend on the general target
            if (found && packages == 1)
              map[source] = package ? File.join(target, package[1].gsub('.', '/'), name.ext(target_ext)) : target
            else
              map[source] = target
            end

          elsif
            map[source] = target
          end
        end

        map.each do |key,value|
          map[key] = first_file unless map[key]
        end

        map
      end
    end

  private

    def count(file, pattern)
      count = 0
      File.open(file, 'r') do |infile|
        while (line = infile.gets)
          count += 1 if line.match(pattern)
        end
      end
      count
    end

    def java_sources(sources)
      sources.flatten.map { |source| File.directory?(source) ? FileList["#{source}/**/*.java"] : source } .
        flatten.reject { |file| File.directory?(file) || File.extname(file) != '.java' }.map { |file| File.expand_path(file) }.uniq
    end

    # Returns Kotlinc arguments from the set of options.
    def kotlinc_args #:nodoc:
      compilerArguments = Java.org.jetbrains.kotlin.cli.common.arguments.K2JVMCompilerArguments.new
      compilerArguments.verbose = options[:debug]
      compilerArguments.suppressWarnings = !options[:warnings]
      compilerArguments.noStdlib = options[:noStdlib]
      compilerArguments.noOptimize = !options[:optimize]
      compilerArguments.reportOutputFiles = compilerArguments.verbose
      compilerArguments.jvmTarget = options[:target] unless options[:target].nil?
      compilerArguments
    end
  end

  module ProjectExtension
    def kotlinc_options
      @kotlinc ||= KotlincOptions.new(self)
    end
  end

  class KotlincOptions
    attr_writer :incremental

    def initialize(project)
      @project = project
    end

    def incremental
      @incremental || (@project.parent ? @project.parent.kotlinc_options.incremental : nil)
    end
  end
end

# Kotlin compiler comes first, ahead of Javac, this allows it to pick
# projects that mix Kotlin and Java code by spotting Kotlin code first.
Buildr::Compiler.compilers.unshift Buildr::Kotlin::Kotlinc

class Buildr::Project #:nodoc:
  include Buildr::Kotlin::ProjectExtension
end
