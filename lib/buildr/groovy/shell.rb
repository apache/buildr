require 'buildr/shell'

module Buildr
  module Groovy
    class GroovySH < Buildr::Shell::Base
      class << self
        def lang
          :groovy
        end
      end
      
      def launch
        # TODO  make this more generic!!
        
        cp = project.compile.dependencies.join(File::PATH_SEPARATOR) + 
          File::PATH_SEPARATOR + project.path_to(:target, :classes)
        
        cmd_args = " -classpath '#{cp}'"
        
        system('groovysh' + cmd_args)
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Groovy::GroovySH
