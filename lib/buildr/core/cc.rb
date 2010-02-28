require 'buildr/core/common'
require 'buildr/core/project'
require 'buildr/core/build'
require 'buildr/core/compile'

module Buildr
  module CC
    include Extension
    
    class << self
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
    
    first_time do
      Project.local_task :cc
    end
    
    before_define do |project|
      project.task :cc => [:compile, 'test:compile'] do
        main_dirs = project.compile.sources.map(&:to_s)
        test_dirs = project.task('test:compile').sources.map(&:to_s)
        res_dirs = project.resources.sources.map(&:to_s)
        
        main_ext = Buildr::Compiler.select(project.compile.compiler).source_ext.map(&:to_s)
        test_ext = Buildr::Compiler.select(project.task('test:compile').compiler).source_ext.map(&:to_s)
        
        test_tail = if test_dirs.empty? then '' else ",{#{test_dirs.join ','}}/**/*.{#{test_ext.join ','}}" end
        res_tail = if res_dirs.empty? then '' else ",{#{res_dirs.join ','}}/**/*" end
        
        pattern = "{{#{main_dirs.join ','}}/**/*.{#{main_ext.join ','}}#{test_tail}#{res_tail}}"
        
        times, _ = Buildr::CC.check_mtime pattern, {}     # establish baseline
        
        dir_names = (main_dirs + test_dirs + res_dirs).map { |file| Buildr::CC.strip_filename project, file }
        if dir_names.length == 1
          info "Monitoring directory: #{dir_names.first}"
        else
          info "Monitoring directories: [#{dir_names.join ', '}]"
        end
        trace "Monitoring extensions: [#{main_ext.join ', '}]"
        
        while true
          sleep project.cc.frequency
          
          times, changed = Buildr::CC.check_mtime pattern, times
          unless changed.empty?
            info ''    # better spacing
            
            changed.each do |file|
              info "Detected changes in #{Buildr::CC.strip_filename project, file}"
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
            
            # TODO  for some reason, resources task doesn't run like this
            project.task(:resources).reenable if in_res
            project.task(:compile).reenable if in_main
            project.task('test:compile').reenable if in_test
            
            project.task(:resources).invoke
            project.task(:compile).invoke
            project.task('test:compile').invoke
          end
        end
      end
    end
    
    def cc
      @cc ||= CCOptions.new
    end
    
    class CCOptions
      attr_writer :frequency      # TODO  this is a bad name, maybe "delay"?
      
      def frequency
        @frequency ||= 0.2
      end
    end
  end
  
  class Project
    include CC
  end
end
