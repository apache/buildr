require 'buildr/shell'

module Buildr
  class JIRB < Buildr::Shell::Base
    class << self
      def lang
        :none
      end
    end
    
    def launch
      fail 'Are we forgetting something? JRUBY_HOME not set.' unless jruby_home
      
      cp = project.compile.dependencies.join(File::PATH_SEPARATOR) + 
        File::PATH_SEPARATOR + project.path_to(:target, :classes)
      
      cp_var = ENV['CLASSPATH']
      if cp_var
        ENV['CLASSPATH'] += File::PATH_SEPARATOR
      else
        ENV['CLASSPATH'] = ''
      end
      ENV['CLASSPATH'] += cp
      
      system(File.expand_path('bin/jirb', jruby_home))
    end
    
  private
    def jruby_home
      @home ||= ENV['JRUBY_HOME']
    end
  end
end

Buildr::ShellProviders << Buildr::JIRB
