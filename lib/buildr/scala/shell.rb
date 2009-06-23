require 'buildr/shell'

module Buildr
  module Scala
    class Shell
      attr_reader :project
      
      class << self
        def lang
          :scala
        end
      end
      
      def initialize(project)
        @project = project
      end
      
      def launch
        Scalac.scala_home or fail 'Are we forgetting something? SCALA_HOME not set.'
        
        cp = (project.compile.dependencies + Scalac.dependencies).join(File::PATH_SEPARATOR) +
          File::PATH_SEPARATOR + project.path_to(:target, :classes)
        
        cmd_args = " -Denv.classpath='#{cp}'"
        cmd_args += ' -classpath'
        cmd_args += " '#{cp}'"
        
        trace "scala #{cmd_args}"
        system(File.expand_path('bin/scala', Scalac.scala_home) + cmd_args)
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Scala::Shell
