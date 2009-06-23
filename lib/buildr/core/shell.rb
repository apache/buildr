require 'buildr/shell'
require 'buildr/java/commands'

module Buildr
  module Shell
    class JIRB < Base
      include JavaRebel
      
      JRUBY_VERSION = '1.1.6'
      
      class << self
        def lang
          :none
        end
      end
      
      def launch
        cp = project.compile.dependencies + [
            "org.jruby:jruby-complete:jar:#{JRUBY_VERSION}",
            project.path_to(:target, :classes)
          ]
        
        Java::Commands.java 'org.jruby.Main', '--command', 'irb', {
          :properties => rebel_props(project),
          :classpath => cp,
          :java_args => rebel_args
        }
      end
      
    private
      def jruby_home
        @home ||= ENV['JRUBY_HOME']
      end
    end
    
    class Clojure < Base
      include JavaRebel
      
      JLINE_VERSION = '0.9.94'
      
      class << self
        def lang
          :none
        end
        
        def to_sym
          :clj      # more common than `clojure`
        end
      end
      
      def launch
        fail 'Are we forgetting something? CLOJURE_HOME not set.' unless clojure_home
        
        cp = project.compile.dependencies + 
          [
            project.path_to(:target, :classes),
            File.expand_path('clojure.jar', clojure_home),
            'jline:jline:jar:0.9.94'
          ]
        
        Java::Commands.java 'jline.ConsoleRunner', 'clojure.lang.Repl', {
          :properties => rebel_props(project),
          :classpath => cp,
          :java_args => rebel_args
        }
      end
      
    private
      def clojure_home
        @home ||= ENV['CLOJURE_HOME']
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Shell::JIRB
Buildr::ShellProviders << Buildr::Shell::Clojure
