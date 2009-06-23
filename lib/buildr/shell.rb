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
    end
  end
  
  module Shell
    include Extension
    
    first_time do
      Project.local_task 'shell'
    end
    
    before_define do |project|
      ShellProviders.providers.each do |lang, p|
        load_provider = proc do |prov|
          name = prov.to_sym
          
          trace "Defining task #{project.name}:shell:#{name}"
          project.task "shell:#{name}" => :compile do
            trace "Launching #{name} shell"
            prov.new(project).launch
          end
        end
        
        if lang == :none
          p.each load_provider
        else
          load_provider.call p
        end
      end
    end
    
    after_define do |project|
      lang = project.compile.language
      default_shell = ShellProviders.providers[lang]
      
      if default_shell
        dep = "shell:#{default_shell.to_sym}"
        
        trace "Defining task shell based on #{dep}"
        project.task :shell => dep
      else
        project.task :shell do
          fail "No shell provider defined for language '#{lang}'"
        end
      end
    end
    
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
      
      def launch
        fail 'Not implemented'
      end
    end
  end
  
  class Project
    include Shell
  end
end
