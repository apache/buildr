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


module Buildr
  module ShellProviders
    class << self
      def add(p)
        @providers ||= {}

        if p.lang == :none
          @providers[:none] ||= []
          @providers[:none] << p
        else
          @providers[p.lang] = p
        end
      end
      alias :<< :add

      def providers
        @providers ||= {}
      end

      def each
        providers.each do |lang, p|
          if lang == :none
            p.each do |x|
              yield x
            end
          else
            yield p
          end
        end
      end
    end
  end

  module Shell
    class Base
      attr_reader :project

      class << self
        def lang
          :none
        end

        def to_sym
          @symbol ||= name.split('::').last.downcase.to_sym
        end
      end

      def initialize(project)
        @project = project
      end

      def build?
        true
      end

      def launch
        fail 'Not implemented'
      end
    end

    module JavaRebel
      def rebel_home
        unless @rebel_home
          @rebel_home = ENV['REBEL_HOME'] || ENV['JREBEL'] || ENV['JREBEL_HOME']

          if @rebel_home and File.directory? @rebel_home
            @rebel_home += File::SEPARATOR + 'jrebel.jar'
          end
        end

        if @rebel_home and File.exists? @rebel_home
          @rebel_home
        else
          nil
        end
      end

      def rebel_args
        if rebel_home
          [
            '-noverify',
            "-javaagent:#{rebel_home}"
          ]
        else
          []
        end
      end

      def rebel_props(project)
        {}
      end
    end
  end

  module ShellExtension
    include Extension

    first_time do
      Project.local_task 'shell'

      ShellProviders.each { |p| Project.local_task "shell:#{p.to_sym}" }    # TODO  not working
    end

    before_define(:shell => :compile) do |project|
      ShellProviders.each do |p|
        name = p.to_sym

        trace "Defining task #{project.name}:shell:#{name}"

        p_inst = p.new project
        deps = if p_inst.build? then [:compile] else [] end

        project.task "shell:#{name}" => deps do
          trace "Launching #{name} shell"
          p_inst.launch
        end
      end
    end

    after_define(:shell => :compile) do |project|
      default_shell = project.shell.using

      if default_shell
        dep = "shell:#{default_shell.to_sym}"

        trace "Defining task shell based on #{dep}"
        project.task :shell => dep
      else
        project.task :shell do
          fail "No shell provider defined for language '#{project.compile.language}'"
        end
      end
    end

    class ShellConfig
      def initialize(project)
        @project = project
      end

      def using(*args)
        if args.size > 0
          @using ||= args.first
        else
          @using ||= find_shell_task
        end
      end

    private
      def find_shell_task
        lang = @project.compile.language
        ShellProviders.providers[lang]
      end
    end

    # TODO  temporary hack
    def shell
      @shell ||= ShellConfig.new self
    end
  end

  class Project
    include ShellExtension
  end
end
