# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.


require 'buildr/shell'
require 'buildr/java/commands'
require 'buildr/core/util'

module Buildr
  module Shell

    class BeanShell < Base
      
      include JavaRebel
      
      VERSION = '2.0b4'

      class << self
        def version
          Buildr.settings.build['bsh'] || VERSION
        end
        
        def artifact
          "org.beanshell:bsh:jar:#{version}"
        end
        
        def lang
          :java
        end
        
        def to_sym
          :bsh
        end
      end
      
      def launch
        cp = project.compile.dependencies + [project.path_to(:target, :classes), Buildr.artifact(BeanShell.artifact)]
        Java::Commands.java 'bsh.Console', {
          :properties => rebel_props(project),
          :classpath => cp,
          :java_args => rebel_args
        }
      end
      
    end # BeanShell

        
    class JIRB < Base
      include JavaRebel
      
      JRUBY_VERSION = '1.4.0'
      
      class << self        
        def lang
          :none
        end
      end
      
      def launch
        if jruby_home     # if JRuby is installed, use it
          cp = project.compile.dependencies + 
            [project.path_to(:target, :classes)] +
            Dir.glob("#{jruby_home}#{File::SEPARATOR}lib#{File::SEPARATOR}*.jar")
          
          props = {
            'jruby.home' => jruby_home,
            'jruby.lib' => "#{jruby_home}#{File::SEPARATOR}lib"
          }
          
          if not Util.win_os?
            uname = `uname -m`
            cpu = if uname =~ /i[34567]86/
              'i386'
            elsif uname == 'i86pc'
              'x86'
            elsif uname =~ /amd64|x86_64/
              'amd64'
            end
            
            os = `uname -s | tr '[A-Z]' '[a-z]'`
            path = if os == 'darwin'
              'darwin'
            else
              "#{os}-#{cpu}"
            end
            
            props['jna.boot.library.path'] = "#{jruby_home}/lib/native/#{path}"
          end
          
          props['jruby.script'] = if Util.win_os? then 'jruby.bat' else 'jruby' end
          props['jruby.shell'] = if Util.win_os? then 'cmd.exe' else '/bin/sh' end
          
          args = [
            "-Xbootclasspath/a:#{Dir.glob("#{jruby_home}#{File::SEPARATOR}lib#{File::SEPARATOR}jruby*.jar").join File::PATH_SEPARATOR}"
          ]
          
          Java::Commands.java 'org.jruby.Main', "#{jruby_home}#{File::SEPARATOR}bin#{File::SEPARATOR}jirb", {
            :properties => props.merge(rebel_props(project)),
            :classpath => cp,
            :java_args => args + rebel_args
          }
        else
          cp = project.compile.dependencies + [
              jruby_artifact,
              project.path_to(:target, :classes)
            ]
          
          Java::Commands.java 'org.jruby.Main', '--command', 'irb', {
            :properties => rebel_props(project),
            :classpath => cp,
            :java_args => rebel_args
          }
        end
      end
    private
      def jruby_home
        @jruby_home ||= RUBY_PLATFORM =~ /java/ ? Config::CONFIG['prefix'] : ENV['JRUBY_HOME']
      end

      def jruby_artifact
        version = Buildr.settings.build['jruby'] || JRUBY_VERSION
        "org.jruby:jruby-complete:jar:#{version}"
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
      
      # don't build if it's *only* Clojure sources
      def build?
        !has_source?(:clojure) or has_source?(:java) or has_source?(:scala) or has_source?(:groovy)
      end
      
      def launch
        fail 'Are we forgetting something? CLOJURE_HOME not set.' unless clojure_home
        
        cp = project.compile.dependencies + 
          [
            if build?
              project.path_to(:target, :classes)
            else
              project.path_to(:src, :main, :clojure)
            end,
            File.expand_path('clojure.jar', clojure_home),
            'jline:jline:jar:0.9.94'
          ]
        
        if build?
          Java::Commands.java 'jline.ConsoleRunner', 'clojure.lang.Repl', {
            :properties => rebel_props(project),
            :classpath => cp,
            :java_args => rebel_args
          }
        else
          Java::Commands.java 'jline.ConsoleRunner', 'clojure.lang.Repl', :classpath => cp
        end
      end
      
    private
      def clojure_home
        @home ||= ENV['CLOJURE_HOME']
      end
      
      def has_source?(lang)
        File.exists? project.path_to(:src, :main, lang)
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Shell::BeanShell
Buildr::ShellProviders << Buildr::Shell::JIRB
Buildr::ShellProviders << Buildr::Shell::Clojure
