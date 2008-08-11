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


require 'highline/import'
require 'rake'
require 'rubygems/source_info_cache'
require 'buildr/core/application_cli'
require 'buildr/core/util'


# Gem::user_home is nice, but ENV['HOME'] lets you override from the environment.
ENV["HOME"] ||= File.expand_path(Gem::user_home)
ENV['BUILDR_ENV'] ||= 'development'


module Buildr

  # Provide settings that come from three sources.
  #
  # User settings are placed in the .buildr/settings.yaml file located in the user's home directory.
  # The should only be used for settings that are specific to the user and applied the same way
  # across all builds.  Example for user settings are preferred repositories, path to local repository,
  # user/name password for uploading to remote repository.
  #
  # Build settings are placed in the build.yaml file located in the build directory.  They help keep
  # the buildfile and build.yaml file simple and readable, working to the advantages of each one.
  # Example for build settings are gems, repositories and artifacts used by that build.
  #
  # Profile settings are placed in the profiles.yaml file located in the build directory.  They provide
  # settings that differ in each environment the build runs in.  For example, URLs and database
  # connections will be different when used in development, test and production environments.
  # The settings for the current environment are obtained by calling #profile.
  class Settings

    def initialize(application) #:nodoc:
      @application = application
      @user = load_from('settings', @application.home_dir)
      @build = load_from('build')
      @profiles = load_from('profiles')
    end

    # User settings loaded from setting.yaml file in user's home directory.
    attr_reader :user

    # Build settings loaded from build.yaml file in build directory.
    attr_reader :build

    # Profiles loaded from profiles.yaml file in build directory.
    attr_reader :profiles

    # :call-seq:
    #    profile => hash
    #
    # Returns the profile for the current environment.
    def profile
      profiles[@application.environment] ||= {}
    end

  private

    def load_from(base_name, dir = nil)
      file_name = ['yaml', 'yml'].map { |ext| File.expand_path("#{base_name}.#{ext}", dir) }.find { |fn| File.exist?(fn) }
      return {} unless file_name
      yaml = YAML.load(File.read(file_name)) || {}
      fail "Expecting #{file_name} to be a map (name: value)!" unless Hash === yaml
      @application.build_files << file_name
      yaml
    end

  end


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
      parse_options
      collect_tasks
      @home_dir = File.expand_path('.buildr', ENV['HOME'])
      mkpath @home_dir unless File.exist?(@home_dir)
      @environment = ENV['BUILDR_ENV'] ||= 'development'
      @on_completion = []
      @on_failure = []
    end

    # Returns list of Gems associated with this buildfile, as listed in build.yaml.
    # Each entry is of type Gem::Specification.
    attr_reader :gems

    # Buildr home directory, .buildr under user's home directory.
    attr_reader :home_dir

    # Copied from BUILD_ENV.
    attr_reader :environment

    # Returns the Settings associated with this build.
    def settings
      @settings ||= Settings.new(self)
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
      Array(settings.build['gems']).map do |dep|
        name, trail = dep.scan(/^\s*(\S*)\s*(.*)\s*$/).first
        versions = trail.scan(/[=><~!]{0,2}\s*[\d\.]+/)
        versions = ['>= 0'] if versions.empty?
        dep = Gem::Dependency.new(name, versions)
        Gem::SourceIndex.from_installed_gems.search(dep).last || dep
      end
    end
    private :listed_gems

    def run
      standard_exception_handling do
        find_buildfile
        load_gems
        load_artifacts
        load_tasks
        load_buildfile
        task('buildr:initialize').invoke
        top_level
      end
      title, message = 'Your build has completed', "#{Dir.pwd}\nbuildr #{@top_level_tasks.join(' ')}"
      @on_completion.each { |block| block.call(title, message) rescue nil }
    end

    # Load artifact specs from the build.yaml file, making them available 
    # by name ( ruby symbols ).
    def load_artifacts #:nodoc:
      hash = settings.build['artifacts']
      return unless hash
      raise "Expected 'artifacts' element to be a hash" unless Hash === hash
      # Currently we only use one artifact namespace to rule them all. (the root NS)
      Buildr::ArtifactNamespace.load(:root => hash)
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
          Util.ruby 'install', spec.name, '-v', spec.version.to_s, :command => 'gem', :sudo => true, :verbose => false
          Gem.source_index.load_gems_in Gem::SourceIndex.installed_spec_directories
        end
        installed += install
      end

      installed.each do |spec|
        if gem(spec.name, spec.version.to_s)
        #  FileList[spec.require_paths.map { |path| File.expand_path("#{path}/*.rb", spec.full_gem_path) }].
        #    map { |path| File.basename(path) }.each { |file| require file }
        #  FileList[File.expand_path('tasks/*.rake', spec.full_gem_path)].each do |file|
        #    Buildr.application.add_import file
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

    def display_prerequisites
      invoke_task('buildr:initialize')
      tasks.each do |task|
        if task.name =~ options.show_task_pattern
          puts "buildr #{task.name}"
          task.prerequisites.each { |prereq| puts "    #{prereq}" }
        end
      end
    end

    # :call-seq:
    #   deprecated(message)
    #
    # Use with deprecated methods and classes. This method automatically adds the file name and line number,
    # and the text 'Deprecated' before the message, and eliminated duplicate warnings. It only warns when
    # running in verbose mode.
    #
    # For example:
    #   deprecated 'Please use new_foo instead of foo.'
    def deprecated(message) #:nodoc:
      return unless verbose
      "#{caller[1]}: Deprecated: #{message}".tap do |message|
        @deprecated ||= {}
        unless @deprecated[message]
          @deprecated[message] = true
          warn message
        end
      end
    end

    # Not for external consumption.
    def switch_to_namespace(names) #:nodoc:
      current, @scope = @scope, names
      begin
        yield
      ensure
        @scope = current
      end
    end
    
    # Yields to block on successful completion. Primarily used for notifications.
    def on_completion(&block)
      @on_completion << block
    end

    # Yields to block on failure with exception. Primarily used for notifications.
    def on_failure(&block)
      @on_failure << block
    end

  private

    # Provide standard execption handling for the given block.
    def standard_exception_handling
      begin
        yield
      rescue SystemExit => ex
        # Exit silently with current status
        exit(ex.status)
      rescue SystemExit, GetoptLong::InvalidOption => ex
        # Exit silently
        exit(1)
      rescue Exception => ex
        title, message = 'Your build failed with an error', "#{Dir.pwd}:\n#{ex.message}"
        @on_failure.each { |block| block.call(title, message, ex) rescue nil }
        # Exit with error message
        $stderr.puts "buildr aborted!"
        $stderr.puts $terminal.color(ex.message, :red)
        if options.trace
          $stderr.puts ex.backtrace.join("\n")
        else
          $stderr.puts ex.backtrace.select { |str| str =~ /#{buildfile}/ }.map { |line| $terminal.color(line, :red) }.join("\n")
          $stderr.puts "(See full trace by running task with --trace)"
        end
        exit(1)
      end
    end
    
  end


  class << self

    task 'buildr:initialize' do
      Buildr.load_tasks_and_local_files
    end

    # Returns the Buildr::Application object.
    def application
      Rake.application
    end

    def application=(app) #:nodoc:
      Rake.application = app
    end

    # Returns the Settings associated with this build.
    def settings
      Buildr.application.settings
    end

    # Copied from BUILD_ENV.
    def environment
      Buildr.application.environment
    end

  end

  Buildr.application = Buildr::Application.new

end


# Add a touch of color when available and running in terminal.
if $stdout.isatty
  begin
    require 'Win32/Console/ANSI' if Config::CONFIG['host_os'] =~ /mswin/
    HighLine.use_color = true
  rescue LoadError
  end
else
  HighLine.use_color = false
end


# We only do this when running from the console in verbose mode.
if $stdout.isatty && verbose
  # Send notifications using BUILDR_NOTIFY environment variable, if defined 
  if ENV['BUILDR_NOTIFY'] && ENV['BUILDR_NOTIFY'].length > 0
    notify = lambda do |type, title, message|
      require 'shellwords'
      args = { '{type}'=>type, '{title}'=>title, '{message}'=>message }
      system Shellwords.shellwords(ENV['BUILDR_NOTIFY']).map { |arg| args[arg] || arg }.map(&:inspect).join(' ')
    end  
    Buildr.application.on_completion { |title, message| notify['completed', title, message] }
    Buildr.application.on_failure { |title, message, ex| notify['failed', title, message] }
  elsif RUBY_PLATFORM =~ /darwin/
    # Let's see if we can use Growl.  We do this at the very end, loading Ruby Cocoa
    # could slow the build down, so later is better.
    notify = lambda do |type, title, message|
      require 'osx/cocoa'
      icon = OSX::NSApplication.sharedApplication.applicationIconImage
      icon = OSX::NSImage.alloc.initWithContentsOfFile(File.join(File.dirname(__FILE__), '../resources/buildr.icns'))

      # Register with Growl, that way you can turn notifications on/off from system preferences.
      OSX::NSDistributedNotificationCenter.defaultCenter.
        postNotificationName_object_userInfo_deliverImmediately(:GrowlApplicationRegistrationNotification, nil,
          { :ApplicationName=>'Buildr', :AllNotifications=>['Completed', 'Failed'], 
            :ApplicationIcon=>icon.TIFFRepresentation }, true)

      OSX::NSDistributedNotificationCenter.defaultCenter.
        postNotificationName_object_userInfo_deliverImmediately(:GrowlNotification, nil,
          { :ApplicationName=>'Buildr', :NotificationName=>type,
            :NotificationTitle=>title, :NotificationDescription=>message }, true)
    end
    Buildr.application.on_completion { |title, message| notify['Completed', title, message] }
    Buildr.application.on_failure { |title, message, ex| notify['Failed', title, message] }
  end
end


alias :warn_without_color :warn

# Show warning message.
def warn(message)
  warn_without_color $terminal.color(message.to_s, :blue) if verbose
end

# Show error message.  Use this when you need to show an error message and not throwing
# an exception that will stop the build.
def error(message)
  puts $terminal.color(message.to_s, :red)
end

# Show optional information.  The message is printed only when running in verbose
# mode (the default).
def info(message)
  puts message if verbose
end

# Show message.  The message is printed out only when running in trace mode.
def trace(message)
  puts message if Buildr.application.options.trace
end


module Rake #:nodoc
  class Task #:nodoc:
    def invoke(*args)
      task_args = TaskArguments.new(arg_names, args)
      invoke_with_call_chain(task_args, Thread.current[:rake_chain] || InvocationChain::EMPTY)
    end

    def invoke_with_call_chain(task_args, invocation_chain)
      new_chain = InvocationChain.append(self, invocation_chain)
      @lock.synchronize do
        if application.options.trace
          puts "** Invoke #{name} #{format_trace_flags}"
        end
        return if @already_invoked
        @already_invoked = true
        invoke_prerequisites(task_args, new_chain)
        begin
          old_chain, Thread.current[:rake_chain] = Thread.current[:rake_chain], new_chain
          execute(task_args) if needed?
        ensure
          Thread.current[:rake_chain] = nil
        end
      end
    end
  end
end
