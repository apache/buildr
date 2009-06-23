require 'buildr/shell'
require 'buildr/java/commands'

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
        
        cp = project.compile.dependencies + Scalac.dependencies +
          [
            project.path_to(:target, :classes)
          ]
        
        props = { 
          'env.classpath' => cp.join(File::PATH_SEPARATOR),
          'scala.home' => Scalac.scala_home
        }
        
        cmd_args = if rebel_home
          trace 'Running Scala shell with JavaRebel'
          
          props['rebel.dirs'] = project.path_to(:target, :classes)
          
          [
            '-noverify',
            "-javaagent:#{rebel_home}"
          ]
        else
          trace 'Running Scala shell'
          []
        end
        
        Java::Commands.java 'scala.tools.nsc.MainGenericRunner', {
          :properties => props,
          :classpath => cp,
          :java_args => cmd_args
        }
      end
      
    private
      
      def rebel_home
        unless @rebel_home
          @rebel_home = ENV['REBEL_HOME'] or ENV['JAVA_REBEL'] or ENV['JAVAREBEL'] or ENV['JAVAREBEL_HOME']
          
          if @rebel_home and File.directory? @rebel_home
            @rebel_home += File::SEPARATOR + 'javarebel.jar'
          end
        end
        
        if @rebel_home and File.exists? @rebel_home
          @rebel_home
        else
          nil
        end
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Scala::ScalaShell
