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
      
      def launch
        fail 'Not implemented'
      end
    end
  end
  
  module ShellExtension
    include Extension
    
    first_time do
      Project.local_task 'shell'
      
      ShellProviders.each { |p| Project.local_task "shell:#{name}" }
    end
    
    before_define do |project|
      ShellProviders.each do |p|
        name = p.to_sym
        
        trace "Defining task #{project.name}:shell:#{name}"
        project.task "shell:#{name}" => :compile do
          trace "Launching #{name} shell"
          p.new(project).launch
        end
      end
    end
    
    after_define do |project|
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
