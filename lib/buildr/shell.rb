module Buildr
  module ShellProviders
    
    class << self
      def add(p)
        @providers ||= {}
        @providers[p.lang] = p
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
    
    after_define do |project|
      project.task 'shell' => :compile do
        lang = project.compile.language
        trace "Launching shell based on language #{lang}"
        
        p = ShellProviders.providers[lang]
        
        if p
          p.new(project).launch
        else
          fail "No shell provider defined for language #{lang}"
        end
      end
    end
  end
  
  class Project
    include Shell
  end
end
