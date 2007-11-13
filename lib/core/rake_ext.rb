module Rake #:nodoc
  class Task #:nodoc:

    def invoke()
      fail "Circular dependency " + (stack + [name]).join("=>") if stack.include?(name)
      @lock.synchronize do
        puts "** Invoke #{name} #{format_trace_flags}" if application.options.trace
        return if @already_invoked
        begin
          stack.push name
          @already_invoked = true
          invoke_prerequisites
          execute if needed?
        ensure
          stack.pop
        end
      end
    end

    def execute
      if application.options.dryrun
        puts "** Execute (dry run) #{name}"
        return
      end
      puts "** Execute #{name}" if application.options.trace
      application.enhance_with_matching_rule(name) if @actions.empty?
      @actions.each { |act| result = act.call(self) }
    end

    def invoke_prerequisites()
      prerequisites.each { |n| application[n, @scope].invoke }
    end

    def inspect()
      "#{self.class}: #{name}"
    end

  protected

    def stack()
      Thread.current[:rake_stack] ||= []
    end

  end

  class MultiTask #:nodoc:
    def invoke_prerequisites()
      threads = @prerequisites.collect do |p|
        copy = stack.dup
        Thread.new(p) { |r| stack.replace copy ; application[r].invoke }
      end
      threads.each { |t| t.join }
    end
  end

  class Application #:nodoc:

    def in_namespace_with_global_scope(name, &block)
      if name =~ /^:/
        begin
          scope, @scope = @scope, name.split(":")[1...-1]
          in_namespace_without_global_scope name.split(":").last, &block
        ensure
          @scope = scope
        end
      else
        in_namespace_without_global_scope name, &block
      end
    end
    alias_method_chain :in_namespace, :global_scope

  end

  class FileList
    class << self
      def recursive(*dirs)
        FileList[dirs.map { |dir| File.join(dir, "/**/{*,.*}") }].reject { |file| File.basename(file) =~ /^[.]{1,2}$/ }
      end
    end
  end
end
