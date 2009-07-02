require 'buildr/shell'
require 'buildr/java/commands'

module Buildr
  module Scala
    class ScalaShell < Buildr::Shell::Base
      include Buildr::Shell::JavaRebel
      
      class << self
        def lang
          :scala
        end
        
        def to_sym
          :scala
        end
      end
      
      def launch
        cp = project.compile.dependencies + 
          Scalac.dependencies +
          [project.path_to(:target, :classes)]
        
        props = {
          'env.classpath' => cp.join(File::PATH_SEPARATOR),
          'scala.home' => Scalac.scala_home
        }
        
        Java::Commands.java 'scala.tools.nsc.MainGenericRunner', {
          :properties => props.merge(rebel_props(project)),
          :classpath => cp,
          :java_args => rebel_args
        }
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Scala::ScalaShell
