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


module Buildr

  # Gem::user_home is nice, but ENV['HOME'] lets you override from the environment.
  ENV["HOME"] ||= File.expand_path(Gem::user_home)

  # When running from +rake+, we already have an Application setup and must plug into it,
  # since the top-level tasks come from there. When running from +buildr+, we get to load
  # Rake and set everything up, and we use our own Application full of cool Buildr features.
  if defined?(Rake)
    Rake.application.top_level_tasks.unshift task('buildr:initialize')
  else

    require 'rake'

    class Application < Rake::Application #:nodoc:

      DEFAULT_BUILDFILES = ['buildfile', 'Buildfile'] + DEFAULT_RAKEFILES
      
      require 'buildr/core/application_cli'
      include CommandLineInterface

      attr_reader :rakefiles, :requires
      private :rakefiles, :requires

      def initialize()
        super
        @rakefiles = DEFAULT_BUILDFILES
        @name = 'Buildr'
        @requires = []
        @top_level_tasks = []
        parse_options
        collect_tasks
        top_level_tasks.unshift 'buildr:initialize'
      end

      def run()
        times = Benchmark.measure do
          standard_exception_handling do
            find_buildfile
            load_buildfile
            top_level
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

      def find_buildfile()
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

      def load_buildfile()
        @requires.each { |name| require name }
        puts Buildr.environment ? "(in #{Dir.pwd}, #{Buildr.environment})" : "(in #{Dir.pwd})"
        load File.expand_path(@rakefile) if @rakefile != ''
        load_imports
      end

    end

    Rake.application = Buildr::Application.new
  end


  class << self

    # Loads buildr.rake files from users home directory and project directory.
    # Loads custom tasks from .rake files in tasks directory.
    def load_tasks_and_local_files() #:nodoc:
      return false if @build_files
      # Load the settings files.
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

    # :call-seq:
    #   build_files() => files
    #
    # Returns a list of build files. These are files used by the build, 
    def build_files()
      [Rake.application.rakefile].compact + @build_files
    end

    task 'buildr:initialize' do
      Buildr.load_tasks_and_local_files
    end

  end

end
