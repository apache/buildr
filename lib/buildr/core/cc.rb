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

require 'buildr/core/common'
require 'buildr/core/project'
require 'buildr/core/build'
require 'buildr/core/compile'

module Buildr
  class CCTask < Rake::Task
    attr_accessor :delay
    attr_reader :project

    def initialize(*args)
      super
      @delay = 0.2
      enhance do
        monitor_and_compile
      end
    end

  private

    def associate_with(project)
      @project = project
    end

    def monitor_and_compile
      # we don't want to actually fail if our dependencies don't succede
      begin
        [:compile, 'test:compile'].each { |name| project.task(name).invoke }
        notify_build_status(true, project)
      rescue Exception => ex
        $stderr.puts $terminal.color(ex.message, :red)
        $stderr.puts

        notify_build_status(false, project)
      end

      main_dirs = project.compile.sources.map(&:to_s)
      test_dirs = project.task('test:compile').sources.map(&:to_s)
      res_dirs = project.resources.sources.map(&:to_s)
      
      main_ext = Buildr::Compiler.select(project.compile.compiler).source_ext.map(&:to_s) unless project.compile.compiler.nil?
      test_ext = Buildr::Compiler.select(project.task('test:compile').compiler).source_ext.map(&:to_s) unless project.task('test:compile').compiler.nil?

      test_tail = if test_dirs.empty? then '' else ",{#{test_dirs.join ','}}/**/*.{#{test_ext.join ','}}" end
      res_tail = if res_dirs.empty? then '' else ",{#{res_dirs.join ','}}/**/*" end

      pattern = "{{#{main_dirs.join ','}}/**/*.{#{main_ext.join ','}}#{test_tail}#{res_tail}}"

      times, _ = check_mtime pattern, {}     # establish baseline

      dir_names = (main_dirs + test_dirs + res_dirs).map { |file| strip_filename project, file }
      if dir_names.length == 1
        info "Monitoring directory: #{dir_names.first}"
      else
        info "Monitoring directories: [#{dir_names.join ', '}]"
      end
      trace "Monitoring extensions: [#{main_ext.join ', '}]"

      while true
        sleep delay

        times, changed = check_mtime pattern, times
        unless changed.empty?
          info ''    # better spacing

          changed.each do |file|
            info "Detected changes in #{strip_filename project, file}"
          end

          in_main = main_dirs.any? do |dir|
            changed.any? { |file| file.index(dir) == 0 }
          end

          in_test = test_dirs.any? do |dir|
            changed.any? { |file| file.index(dir) == 0 }
          end

          in_res = res_dirs.any? do |dir|
            changed.any? { |file| file.index(dir) == 0 }
          end

          project.task(:compile).reenable if in_main
          project.task('test:compile').reenable if in_test || in_main

          successful = true
          begin
            project.task(:resources).filter.run if in_res
            project.task(:compile).invoke if in_main
            project.task('test:compile').invoke if in_test || in_main
          rescue Exception => ex
            $stderr.puts $terminal.color(ex.message, :red)
            successful = false
          end

          notify_build_status(successful, project)
          puts $terminal.color("Build complete", :green) if successful
        end
      end
    end

    def notify_build_status(successful, project)
       if RUBY_PLATFORM =~ /darwin/ && $stdout.isatty && verbose
         if successful
           growl_notify('Completed', 'Your build has completed', project.path_to)
         else
           growl_notify('Failed', 'Your build has failed with an error', project.path_to)
         end
       end
    end

    def check_mtime(pattern, old_times)
      times = {}
      changed = []

      Dir.glob pattern do |fname|
        times[fname] = File.mtime fname
        if old_times[fname].nil? || old_times[fname] < File.mtime(fname)
          changed << fname
        end
      end

      # detect deletion (slower than it could be)
      old_times.each_key do |fname|
        changed << fname unless times.has_key? fname
      end

      [times, changed]
    end

    def strip_filename(project, name)
      name.gsub project.base_dir + File::SEPARATOR, ''
    end
  end

  module CC
    include Extension

    first_time do
      desc 'Execute continuous compilation, listening to changes'
      Project.local_task('cc') { |name|  "Executing continuous compilation for #{name}" }
    end

    before_define do |project|
      cc = CCTask.define_task :cc
      cc.send :associate_with, project
      project.recursive_task(:cc)
    end

    def cc
      task :cc
    end
  end

  class Project
    include CC
  end
end
