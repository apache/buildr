module Buildr
  module CC
    include Extension
    
    class << self
      def check_mtime(dirs, ext, old_times)
        times = old_times
        changed = []
        
        dirs.each do |dir|
          Dir.glob "#{dir}/**/*.{#{ext.join ','}}" do |fname|
            if old_times[fname].nil? || old_times[fname] < File.mtime(fname)
              times[fname] = File.mtime fname
              changed << fname
            end
          end
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
      project.task :cc => :compile do
        dirs = project.compile.sources.map(&:to_s)
        ext = Buildr::Compiler.select(project.compile.compiler).source_ext.map(&:to_s)
        times, _ = Buildr::CC.check_mtime dirs, ext, {}     # establish baseline
        
        dir_names = dirs.map { |file| Buildr::CC.strip_filename project, file }
        if dirs.length == 1
          info "Monitoring directory: #{dir_names.first}"
        else
          info "Monitoring directories: [#{dir_names.join ', '}]"
        end
        trace "Monitoring extensions: [#{ext.join ', '}]"
        
        while true
          sleep 0.2
          
          times, changed = Buildr::CC.check_mtime dirs, ext, times
          unless changed.empty?
            info ''    # better spacing
            
            changed.each do |file|
              info "Detected changes in #{Buildr::CC.strip_filename project, file}"
            end
            
            project.task(:compile).reenable
            project.task(:compile).invoke
          end
        end
      end
    end
  end
  
  class Project
    include CC
  end
end
