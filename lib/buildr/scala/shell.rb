require 'buildr/shell'

module Buildr
  module Scala
    class ScalaShell < Buildr::Shell::Base
      SUFFIX = if Util.win_os? then '.bat' else '' end
      
      class << self
        def lang
          :scala
        end
        
        def to_sym
          :scala
        end
      end
      
      def launch
        Scalac.scala_home or fail 'Are we forgetting something? SCALA_HOME not set.'
        
        cp = (project.compile.dependencies + Scalac.dependencies).join(File::PATH_SEPARATOR) +
          File::PATH_SEPARATOR + project.path_to(:target, :classes)
        
        cmd_args = " -Denv.classpath='#{cp}'"
        cmd_args += ' -classpath'
        cmd_args += " '#{cp}'"
        
        trace "scala #{cmd_args}"
        system(File.expand_path('bin/scala' + SUFFIX, Scalac.scala_home) + cmd_args)
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Scala::ScalaShell
