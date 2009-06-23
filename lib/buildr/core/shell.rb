require 'buildr/shell'

module Buildr
  module Shell
    class JIRB < Base
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
    
    class Clojure < Base
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
        fail 'Are we forgetting something? JLINE_JAR not set.' unless jline_jar
        
        cp = project.compile.dependencies.join(File::PATH_SEPARATOR) + 
          File::PATH_SEPARATOR + project.path_to(:target, :classes) +
          File::PATH_SEPARATOR + File.expand_path('clojure.jar', clojure_home) +
          File::PATH_SEPARATOR + jline_jar
        
        system("java -classpath '#{cp}' jline.ConsoleRunner clojure.lang.Repl")
      end
      
    private
      def clojure_home
        @home ||= ENV['CLOJURE_HOME']
      end
      
      # TODO
      def jline_jar
        @jline ||= ENV['JLINE_JAR']
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Shell::JIRB
Buildr::ShellProviders << Buildr::Shell::Clojure
