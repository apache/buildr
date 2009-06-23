require 'buildr/shell'

module Buildr
  module Groovy
    class Shell
      attr_reader :project
      
      class << self
        def lang
          :groovy
        end
      end
      
      def initialize(project)
        @project = project
      end
      
      def launch
        # TODO  make this more generic!!
        
        cp = project.compile.dependencies.join(File::PATH_SEPARATOR) + project.path_to(:target, :classes)
        
        cmd_args = " -classpath '#{cp}'"
        
        system('groovysh' + cmd_args)
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Groovy::Shell
