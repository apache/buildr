require 'buildr/shell'

module Buildr
  module Groovy
    class GroovySH < Buildr::Shell::Base
      SUFFIX = if Util.win_os? then '.bat' else '' end
      
      class << self
        def lang
          :groovy
        end
      end
      
      def launch
        fail 'Are we forgetting something? GROOVY_HOME not set.' unless groovy_home
        
        cp = project.compile.dependencies.join(File::PATH_SEPARATOR) + 
          File::PATH_SEPARATOR + project.path_to(:target, :classes)
        
        cmd_args = " -classpath '#{cp}'"
        trace "groovysh #{cmd_args}"
        system(File.expand_path("bin#{File::SEPARATOR}groovysh#{SUFFIX}", groovy_home) + cmd_args)
      end
      
    private
      def groovy_home
        @home ||= ENV['GROOVY_HOME']
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Groovy::GroovySH
