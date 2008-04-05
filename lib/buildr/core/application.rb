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

# Portion of this file derived from Rake.
# Copyright (c) 2003, 2004 Jim Weirich
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


require 'benchmark'
require 'rake'
require 'rubygems/source_info_cache'
require 'buildr/core/application_cli'


# Gem::user_home is nice, but ENV['HOME'] lets you override from the environment.
ENV["HOME"] ||= File.expand_path(Gem::user_home)
ENV['BUILDR_ENV'] ||= 'development'

# Add a touch of colors (red) to warnings.
HighLine.use_color = !Gem.win_platform?


module Buildr

  class Application < Rake::Application #:nodoc:

    DEFAULT_BUILDFILES = ['buildfile', 'Buildfile'] + DEFAULT_RAKEFILES
    
    include CommandLineInterface

    attr_reader :rakefiles, :requires
    private :rakefiles, :requires

    def initialize
      super
      @rakefiles = DEFAULT_BUILDFILES
      @name = 'Buildr'
      @requires = []
      @top_level_tasks = []
      @home_dir = File.expand_path('.buildr', ENV['HOME'])
      @environment = ENV['BUILDR_ENV']
      parse_options
      collect_tasks
      top_level_tasks.unshift 'buildr:initialize'
      mkpath @home_dir unless File.exist?(@home_dir)
    end

    # Returns list of Gems associated with this buildfile, as listed in build.yaml.
    # Each entry is of type Gem::Specification.
    attr_reader :gems

    # Buildr home directory, .buildr under user's home directory.
    attr_reader :home_dir

    # Copied from BUILD_ENV.
    attr_reader :environment

    # User settings loaded from settings.yaml (Hash).
    def settings
      unless @settings
        file_name = ['settings.yaml', 'settings.yml'].map { |fn| File.expand_path(fn, home_dir) }.find { |fn| File.exist?(fn) }
        @settings = file_name && YAML.load(File.read(file_name)) || {}
        fail "Expecting #{file_name} to be a hash!" unless Hash === @settings
      end
      @settings
    end

    # Configuration loaded from build.yaml (Hash).
    def configuration
      unless @config
        file_name = ['build.yaml', 'build.yml'].map { |fn| File.expand_path(fn, File.dirname(buildfile)) }.find { |fn| File.exist?(fn) }
        @config = file_name && YAML.load(File.read(file_name)) || {}
        fail "Expecting #{file_name} to be a hash!" unless Hash === @config
      end
      @config
    end

    # :call-seq:
    #    profile => hash
    #
    # Returns the profile for the current environment.
    def profile
      profiles[environment] ||= {}
    end

    # :call-seq:
    #    profiles => hash
    #
    # Returns all the profiles loaded from the profiles.yaml file.
    def profiles
      unless @profiles
        file_name = ['profiles.yaml', 'profiles.yml'].map { |fn| File.expand_path(fn, File.dirname(buildfile)) }.find { |fn| File.exist?(fn) }
        @profiles = file_name && YAML.load(File.read(file_name)) || {}
        fail "Expecting #{file_name} to be a hash!" unless Hash === @profiles
        @profiles = profiles.inject({}) { |hash, (name, value)| value ||= {} 
          raise 'Each profile must be empty or contain name/value pairs.' unless Hash === value
          hash.merge(name=>(value || {})) }
      end
      @profiles
    end

    # :call-seq:
    #   buildfile
    def buildfile
      rakefile
    end

    # :call-seq:
    #   build_files => files
    #
    # Returns a list of build files. These are files used by the build, 
    def build_files
      [buildfile].compact + Array(@build_files)
    end

    # Returns Gem::Specification for every listed and installed Gem, Gem::Dependency
    # for listed and uninstalled Gem, which is the installed before loading the buildfile.
    def listed_gems #:nodoc:
      Array(configuration['gems']).map do |dep|
        name, trail = dep.scan(/^\s*(\S*)\s*(.*)\s*$/).first
        versions = trail.scan(/[=><~!]{0,2}\s*[\d\.]+/)
        versions = ['>= 0'] if versions.empty?
        dep = Gem::Dependency.new(name, versions)
        Gem::SourceIndex.from_installed_gems.search(dep).last || dep
      end
    end
    private :listed_gems

    def run
      times = Benchmark.measure do
        standard_exception_handling do
          find_buildfile
          load_gems
          load_buildfile
          top_level
          load_tasks
        end
      end
      if verbose
        real = []
        real << ("%ih" % (times.real / 3600)) if times.real >= 3600
        real << ("%im" % ((times.real / 60) % 60)) if times.real >= 60
        real << ("%.3fs" % (times.real % 60))
        puts "Completed in #{real.join}"
      end
    end

    # Load/install all Gems specified in build.yaml file.
    def load_gems #:nodoc:
      missing_deps, installed = listed_gems.partition { |gem| gem.is_a?(Gem::Dependency) }
      unless missing_deps.empty?
        remote = missing_deps.map { |dep| Gem::SourceInfoCache.search(dep).last || dep }
        not_found_deps, install = remote.partition { |gem| gem.is_a?(Gem::Dependency) }
        fail Gem::LoadError, "Build requires the gems #{not_found_deps.join(', ')}, which cannot be found in local or remote repository." unless not_found_deps.empty?
        uses = "This build requires the gems #{install.map(&:full_name).join(', ')}:"
        fail Gem::LoadError, "#{uses} to install, run Buildr interactively." unless $stdout.isatty
        unless agree("#{uses} do you want me to install them? [Y/n]", true)
          fail Gem::LoadError, 'Cannot build without these gems.'
        end
        install.each do |spec|
          say "Installing #{spec.full_name} ... " if verbose
          cmd = Config::CONFIG['ruby_install_name'], '-S', 'gem', 'install', spec.name, '-v', spec.version.to_s
          cmd.unshift 'sudo' unless Gem.win_platform? || RUBY_PLATFORM =~ /java/
          sh *cmd.push(:verbose=>false)
          Gem.source_index.load_gems_in Gem::SourceIndex.installed_spec_directories
        end
        installed += install
      end

      installed.each do |spec|
        if gem(spec.name, spec.version.to_s)
        #  FileList[spec.require_paths.map { |path| File.expand_path("#{path}/*.rb", spec.full_gem_path) }].
        #    map { |path| File.basename(path) }.each { |file| require file }
        #  FileList[File.expand_path('tasks/*.rake', spec.full_gem_path)].each do |file|
        #    Rake.application.add_import file
        #  end
        end
      end
      @gems = installed
    end

    def find_buildfile
      here = Dir.pwd
      while ! have_rakefile
        Dir.chdir('..')
        if Dir.pwd == here || options.nosearch
          error = "No Buildfile found (looking for: #{@rakefiles.join(', ')})"
          if STDIN.isatty
            chdir(original_dir) { task('generate').invoke }
            exit 1
          else
            raise error
          end
        end
        here = Dir.pwd
      end
    end

    def load_buildfile
      @requires.each { |name| require name }
      puts "(in #{Dir.pwd}, #{environment})"
      load File.expand_path(@rakefile) if @rakefile != ''
      load_imports
    end

    # Loads buildr.rake files from users home directory and project directory.
    # Loads custom tasks from .rake files in tasks directory.
    def load_tasks #:nodoc:
      @build_files = [ File.expand_path('buildr.rb', ENV['HOME']), 'buildr.rb' ].select { |file| File.exist?(file) }
      @build_files += [ File.expand_path('buildr.rake', ENV['HOME']), File.expand_path('buildr.rake') ].
        select { |file| File.exist?(file) }.each { |file| warn "Please use '#{file.ext('rb')}' instead of '#{file}'" }
      #Load local tasks that can be used in the Buildfile.
      @build_files += Dir["#{Dir.pwd}/tasks/*.rake"]
      @build_files.each do |file|
        unless $LOADED_FEATURES.include?(file)
          load file
          $LOADED_FEATURES << file
        end
      end
      true
    end
    private :load_tasks

  end


  class << self

    # :call-seq:
    #   build_files => files
    #
    # Returns a list of build files. These are files used by the build, 
    def build_files
      Buildr.application.build_files
    end

    task 'buildr:initialize' do
      Buildr.load_tasks_and_local_files
    end

    # Returns the Buildr::Application object.
    attr_accessor :application

  end

  Buildr.application = Rake.application = Buildr::Application.new

end
