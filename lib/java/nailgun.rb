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

require 'rbconfig'

module Buildr

  #  See the nailgun_help method for documentation.
  module Nailgun # :nodoc:
    extend self
    
    VERSION = '0.7.1'
    NAME = "nailgun-#{VERSION}"
    URL = "http://downloads.sourceforge.net/nailgun/#{NAME}.zip"
    ARTIFACT_SPEC = "com.martiansoftware:nailgun:jar:#{VERSION}"
    
    attr_accessor :artifact
    attr_accessor :server, :port, :jruby_queue_size, :buildr_queue_size
    attr_accessor :jruby_home, :home
    
    self.jruby_home = if PLATFORM =~ /java/
                        Config::CONFIG['prefix']
                      else
                        ENV['JRUBY_HOME'] || File.join(ENV['HOME'], '.jruby')
                      end
    
    self.home = ENV['NAILGUN_HOME'] || File.join(jruby_home, 'tool', 'nailgun')
    self.server = 'localhost'
    self.port = 2113
    self.jruby_queue_size = 3
    self.buildr_queue_size = 3

    def namespace(&block)
      if Object.const_defined?(:Rake)
        Rake.application.in_namespace(:nailgun, &block)
      end
    end

    def boot(&block)
      if block
        @boot = block
      else
        @boot.call
      end
    end

    module Application
      def nailgun_help
        "  " + <<-DESC.strip.gsub(/ *\n +/, "\n  ")
          NailGun is a client, protocol, and server for running Java 
          programs from the command line without incurring the JVM
          startup overhead. Nailgun integration is currently available
          only when running Buildr with JRuby.

          Buildr provides a custom nailgun server, allowing you to 
          start a single JVM and let buildr create a queue of runtimes.
          These JRuby runtimes can be cached (indexed by buildfile path)
          and are automatically reloaded when the buildfile has been modified.
          Runtime caching allows you to execute tasks without
          spending time creating the buildr environment. Some nailgun 
          tasks have been provided to manage the cached runtimes.

          To start the buildr server execute the following task:

              ng:start

          Server output will display a message when it becomes ready, you
          will also see messages when the JRuby runtimes are being created,
          or when a new buildr environment is being loaded on them.
          After the runtime queues have been populated, you can start calling
          buildr as you normally do, by invoking the $NAILGUN_HOME/ng binary:

              # on another terminal, change directory to a project.
              # if this project is the same ng:start was invoked on, it's 
              # runtime has been cached, so no loading is performed unless 
              # the buildfile has been modified. otherwise the buildfile 
              # will be loaded on a previously loaded fresh-buildr runtime
              # and it will be cached.
              cd /some/buildr/project
              ng ng:help                      # display nailgun help
              ng ng:tasks                     # display overview of ng tasks
              ng clean compile                # just invoke those two tasks

             Configuration and Environment Variables.

          Before starting the server, buildr will check if you have 
          nailgun already installed by seeking the nailgun jar under

              $NAILGUN_HOME

          You can override this environment variable to tell buildr where
          to find or where to install nailgun. If missing, NAILGUN_HOME
          defaults to the $JRUBY_HOME/tools/nailgun directory. You can 
          also specify the nailgun_home on your buildfile with the following
          code:
              
              require 'java/nailgun'
              Buildr::Nailgun.home = File.expand_path('~/.jruby/tools/nailgun')

          Buildr will also check that the nailgun client binary (ng.exe for 
          Windows systems, ng otherwise) is installed on NAILGUN_HOME. 
          If no binary is found, buildr will download nailgun and 
          compile+install it.
          
          
          The buildr server binds itself to localhost, port 2113. You can 
          override this on your buildfile, by placing the following code:

              require 'java/nailgun'
              Buildr::Nailgun.server = '127.0.0.1'
              Buildr::Nailgun.port = 2233

          If you provided custom host/port settings you need
          to tell the nailgun client where to connect to:

              ng --nailgun-server 127.0.0.1 --nailgun-port 2233 ng:tasks

          The buildr server starts a BuildrFactory responsible for providing
          a pool of JRuby runtimes configured and ready for task execution. 
          This BuildrFactory consists of two queues: One of pure JRuby runtimes
          with almost nothing loaded, and another of Buildr runtimes (consumed
          from the first queue) with the Buildr runtime preloaded but without
          any project definition. The jruby queue is used for sandboxing code
          like running GetoptLong, but most importantly its the place where 
          buildr runtimes begin life, to be later added on the buildr queue.
          By default both queues are of size 3, you can customize this with:

              require 'java/nailgun'
              Buildr::Nailgun.jruby_queue_size = 4 # JRuby creation is fast!
              Buildr::Nailgun.buildr_queue_size = 5 # loading buildr takes longer

          The buildr_queue_size is of particular importance if you expect to 
          reload lots of buildfiles.
 
            Running buildr using a nailgun client.

          After you have started the nailgun server, you only have to open another
          terminal on a project directory 

          Execute ng:tasks get an overview of available nailgun tasks.
          
        DESC
      end
      
      def nailgun_tasks
        tasks = {}
        tasks['ng:help'] = 'Display nailgun help'
        tasks['ng:start'] = 'Start the Nailgun server.'
        tasks['ng:stop'] = 'Stop the Nailgun server.'
        tasks['ng:tasks'] = 'Display this message'
        tasks['ng:list'] = <<-DESC
                 Display a list of builfile paths having an associated
                 buildr runtime. Having a cached runtime reduces buidlr
                 execution time.

                 If buildr finds the current buildfile on this list, 
                 no file loading will be performed, only execution of 
                 specified tasks on the previously loaded environment. 
                 However if the cached runtime is out of date (buildfile
                 has been modified) the runtime will be reloaded.

                 This feature becomes handy when performing development
                 cycle: edit -> compile -> test -> report. 

                 This task exits inmediatly after printing the file list.
            DESC
        tasks['ng:clear'] = <<-DESC
                 Remove all cached buildr runtimes and exit
            DESC
        tasks[['ng:add [tasks]', 'ng:put [tasks]']] = <<-DESC
                 Add or update a cached runtime.
                 
                 Use this task to create a cached buildr runtime for a 
                 buildfile.
            DESC
        tasks[['ng:del', 'ng:delete']] = <<-DESC
                 Delete cached runtime for a buildfile and exit.
            DESC
        tasks['ng:once [tasks]'] = <<-DESC
                 Ignore cached runtime and perform tasks on a newly 
                 created environment. This new runtime is dropped right
                 after buildr completion.
            DESC
        
        out = ""
        out << "\nNailgun tasks:\n"
        tasks.each_pair do |task, desc|
          out << "\n"
          out << sprintf("  %20-s\n", [task].flatten.join(' | '))
          out << sprintf("      %s\n", desc.strip.gsub(/ *\n +/, "\n      "))
        end
        out
      end
      
      def buildfile(dir = nil, candidates = nil)
        dir ||= Dir.pwd
        candidates ||= @rakefiles.dup
        Util.find_buildfile(dir, candidates, options.nosearch)
      end
      
      def clear_invoked
        tasks.each { |t| t.instance_variable_set(:@already_invoked, false) }
      end

      if Buildr.const_defined?(:Application)
        class Buildr::Application
          include Nailgun::Application
        end
      end
    end
    
    module ContextRunner
      extend self
      
      def parse_options(ctx, opts)
          
        Buildr.const_set(:VERSION, ctx.server.runtime.getObject.
                         const_get(:Buildr)::VERSION)
  
        require 'ostruct'
        obj = OpenStruct.new(:ctx => ctx, :opts => opts)
        class << obj
          require 'core/application_cli'
          include Buildr::CommandLineInterface
          
          def help
            super
            puts 
            puts 'To get a summary of Nailgun features use'
            puts '  ng:help'
          end

          def do_option(opt, value)
            case opt
            when '--help'
              help
              opts.exit = true
            when '--version'
              puts version
              opts.exit = true
            when '--environment'
              ctx.env['BUILDR_ENV'] = value
            when '--buildfile'
              opts.buildfile = value
            when '--nosearch'
              opts.nosearch = true
            end
          end
        end
        
        ARGV.replace(ctx.argv)
        obj.parse_options
      end
      
      def run(ctx)
        ARGV.replace(ctx.argv)
        Dir.chdir(ctx.pwd)
        ctx.env.each { |k, v| ENV[k.to_s] = v.to_s }
        Buildr::Application.module_eval do
          include Nailgun::Application
        end
        Buildr.help do 
          "\nTo get a summary of Nailgun features use" << 
          "\n  ng:help"
        end
        if ctx.fresh
          run_fresh(ctx)
        else
          run_local(ctx)
        end
      end
      
      private
      
      def run_fresh(ctx)
        Project.clear
        old_app = Rake.application
        Rake.application = Buildr::Application.new
        Rake.application.instance_eval do
          @tasks = old_app.instance_variable_get(:@tasks)
          @rules = old_app.instance_variable_get(:@rules)
          run
        end
      end

      def run_local(ctx)
        Rake.application.instance_eval do        
          parse_options
          collect_tasks
          clear_invoked
          top_level_tasks.delete('buildr:initialize')
          Util.benchmark { top_level }
        end
      end
    end

    module Util
      extend self
      
      def timestamp(file)
        if File.exist?(file)
          File.mtime(file)
        else
          Rake::EARLY
        end
      end

      def find_buildfile(pwd, candidates, nosearch=false)
        candidates = [candidates].flatten
        buildfile = candidates.find { |c| File.file?(File.expand_path(c, pwd)) }
        return File.expand_path(buildfile, pwd) if buildfile
        return nil if nosearch
        updir = File.dirname(pwd)
        return nil if File.expand_path(updir) == File.expand_path(pwd)
        find_buildfile(updir, candidates)
      end
      
      def benchmark(action = ['Completed'], verbose = true)
        result = nil
        require 'benchmark'
        times = Benchmark.measure do
          result = yield(action)
        end
        if verbose
          real = []
          real << ("%ih" % (times.real / 3600)) if times.real >= 3600
          real << ("%im" % ((times.real / 60) % 60)) if times.real >= 60
          real << ("%.3fs" % (times.real % 60))
          puts "#{[action].flatten.join(' ')} in #{real.join}"
        end
        result
      end

      def on_runtime(runtime, *args, &block)
        code = %q{
          obj = Object.new
          def obj.runtime_exec(*args, &block)
            (class << self; self; end).
              send(:define_method, :runtime_exec, &block)
            runtime_exec(*args)
          end
          obj
        }
        executor = runtime.evalScriptlet(code)
        executor.runtime_exec(*args, &block)
      end
    end # module Util

    boot do
      require 'jruby'
      
      class ::ConcreteJavaProxy
        def self.jclass(name = nil)
          name ||= self.java_class.name
          Nailgun::Util.class_for_name(name)
        end
        
        def self.jnew(*args)
          objs = []
          classes = args.map do |a|
            case a
            when nil
              obj << nil
              nil
            when Hash
              objs << a.keys.first
              cls = a.values.first
              cls = Nailgun::Util.proxy_class(cls) if String == cls
              cls
            else
              objs << a
              a.java_class
            end
          end
          classes = classes.to_java(java.lang.Class)
          ctor = jclass.getDeclaredConstructor(classes)
          ctor.setAccessible(true)
          ctor.newInstance(objs.to_java(java.lang.Object))
        end
      end

      module Util
        def class_for_name(name)
          java.lang.Class.forName(name)
        end
        
        def add_to_sysloader(path)
          sysloader = java.lang.ClassLoader.system_class_loader
          add_url_method = class_for_name('java.net.URLClassLoader').
            getDeclaredMethod('addURL', [java.net.URL].to_java(java.lang.Class))
          add_url_method.accessible = true
          add_url_method.invoke(sysloader, [java.io.File.new(path.to_s).
                                            toURL].to_java(java.net.URL))
        end
        add_to_sysloader Nailgun.artifact
        
        def proxy_class(name)
          JavaUtilities.get_proxy_class(name)
        end

        import org.jruby.RubyIO 
        def redirect_stdio(runtime, nail)
          result = nil
          stdin  = runtime.global_variables.get('$stdin')
          stdout = runtime.global_variables.get('$stdout')
          stderr = runtime.global_variables.get('$stderr')

          set_in = lambda do |i|
            runtime.global_variables.set('$stdin', i)
            runtime.object.send(:remove_const, 'STDIN')
            runtime.object.send(:const_set, 'STDIN', i)
          end
          
          begin
            input  = RubyIO.jnew(runtime, java.lang.System.in => java.io.InputStream)
            output = RubyIO.jnew(runtime, nail.out => java.io.OutputStream)
            error = RubyIO.jnew(runtime, nail.err => java.io.OutputStream)
            #stdin.reopen(input, 'r') # not working on jruby :(
            set_in.call(input)
            stdout.reopen(output)
            stderr.reopen(error)
            result = yield
          ensure
            input  = RubyIO.jnew(runtime, java.lang.System.in => java.io.InputStream)
            output = RubyIO.jnew(runtime, java.lang.System.out => java.io.OutputStream)
            error = RubyIO.jnew(runtime, java.lang.System.err => java.io.OutputStream)
            set_in.call(input)
            stdout.reopen(output)
            stderr.reopen(error)
          end
          result
        end
      end
      
      class BuildrNail 
        include org.apache.buildr.BuildrNail
        Main = Util.proxy_class 'org.apache.buildr.BuildrNail$Main'
        
        attr_reader :buildfile
        
        def initialize
          @buildfile = Rake.application.buildfile
          @runtimes = { @buildfile => JRuby.runtime }
          @timestamps = { @buildfile => Util.timestamp(@buildfile) }
        end

        def main(nail)
          Thread.exclusive { Thread.current.priority = 100; run(nail) }
        end

        private
        def run(nail)
          nail.assert_loopback_client
          nail.out.println "Using #{nail.getNGServer}"
          ctx = context_from_nail(nail)
          
          case ctx.action
          when :start
            nail.out.println "Cannot start nailgun when running as client"
            return nail.exit(0)
          when :stop
            puts "Stopping #{nail.getNGServer}"
            nail.out.println "Stopping #{nail.getNGServer}"
            return nail.getNGServer.shutdown(true)
          when :list
            nail.out.println "Defined runtimes:"
            @runtimes.each_key { |f| nail.out.println f }
            return nail.exit(0)
          when :clear
            @runtimes.clear
            @timestamps.clear
            nail.out.println "Cleared all runtimes"
            return nail.exit(0)
          when :tasks
            nail.out.println ""
            nail.out.println Rake.application.nailgun_tasks
            return nail.exit(0)
          when :help
            nail.out.println ""
            nail.out.println Rake.application.nailgun_help
            return nail.exit(0)
          end
          
          opts = OpenStruct.new
          
          Util.on_runtime(ctx.runtime) do
            ::Buildr::Nailgun::ContextRunner.parse_options(ctx, opts)
          end
          return nail.exit(0) if opts.exit

          candidates = Buildr::Application::DEFAULT_BUILDFILES
          candidates = [opts.buildfile] if opts.buildfile
          
          buildfile = Util.find_buildfile(ctx.pwd, candidates, opts.nosearch)
          if ctx.action == :delete
            buildfile ||= File.expand_path(candidates.first, ctx.pwd)
            nail.out.println "Deleting runtime for #{buildfile}"
            @runtimes.delete(buildfile)
            @timestamps.delete(buidlfile)
            return nail.exit(0)
          end

          puts "Getting buildr runtime for #{buildfile}"

          if ctx.action.nil? && @timestamps.key?(buildfile) &&
              @timestamps[buildfile] < Util.timestamp(buildfile)
            puts "Reloading runtime for #{buildfile} due to modification"
            ctx.action = :put
          end

          runtime = @runtimes[buildfile]
          if runtime.nil? || [:put, :once].include?(ctx.action)
            runtime = ctx.buildr
            if ctx.action == :put
              @runtimes[buildfile] = runtime
              @timestamps[buildfile] = Util.timestamp(buildfile)
            end
            ctx.fresh = true
          end
          
          Util.on_runtime(runtime) do
            Util.redirect_stdio(runtime, nail) do
              ::Buildr::Nailgun::ContextRunner.run(ctx)
            end
          end
        end
        
        def context_from_nail(nail)
          ctx = OpenStruct.new
          ctx.pwd = nail.getWorkingDirectory
          ctx.env = nail.env
          ctx.argv = [nail.command] + nail.args.map(&:to_s)
          ctx.server = nail.getNGServer
          def ctx.runtime; @runtime ||= server.buildr_factory.runtime; end
          def ctx.buildr; @buildr ||= server.buildr_factory.obtain; end
          actions = {
            :put => %w{ng:add ng:put nailgun:add nailgun:put},
            :delete => %w{ng:del ng:delete nailgun:del nailgun:delete},
            :clear => %w{ng:clear nailgun:clear},
            :list => %w{ng:list nailgun:list},
            :start => %w{ng:boot ng:start nailgun:boot nailgun:start},
            :stop => %w{ng:stop nailgun:stop},
            :once => %w{ng:once nailgun:once},
            :tasks => %w{ng:tasks nailgun:tasks},
            :help => %w{ng:help nailgun:help help:ng help:nailgun},
          }
          action = actions.find { |k,v| k if v.any? { |t| ctx.argv.delete(t) } }
          ctx.action = action.first if action
          ctx
        end
        
      end # class BuildrNail

      class BuildrFactory
        require 'thread'
        require 'monitor'
        
        attr_accessor :buildrs_size, :runtimes_size
        
        def initialize(buildrs_size = 1, runtimes_size = nil)
          runtimes_size ||= buildrs_size
          @buildrs_size = buildrs_size < 1 ? 1 : buildrs_size
          @runtimes_size = runtimes_size < 1 ? 1 : runtimes_size

          @buildrs = [].extend(MonitorMixin)
          @buildrs_ready = @buildrs.new_cond
          @buildrs_create = @buildrs.new_cond
          
          @buildrs_creators = [].extend(MonitorMixin)
          @runtimes_creators = [].extend(MonitorMixin)
          
          @runtimes = [].extend(MonitorMixin)
          @runtimes_ready = @runtimes.new_cond
          @runtimes_create = @runtimes.new_cond
        end
        
        def obtain
          @buildrs.synchronize do
            @buildrs_ready.wait_while { @buildrs.empty? }
            @buildrs_create.signal
            @buildrs.shift
          end
        end

        def runtime
          @runtimes.synchronize do
            @runtimes_ready.wait_while { @runtimes.empty? }
            @runtimes_create.signal
            @runtimes.shift
          end
        end

        def start
          puts "Starting Buildr runtime factory"
          @runtime_creator = Thread.new { loop { create_runtime_when_needed } }
          @buildr_creator = Thread.new { loop { create_buildr_when_needed } }
          @runtime_creator.priority = -2
          @buildr_creator.priority = 1
        end

        def stop
          @buildr_creator.kill if @buildr_creator
          @runtime_creator.kill if @runtime_creator
        end

        private
        def may_create_runtime?
          @runtimes.synchronize do
            count = @runtimes.size
            if count < runtimes_size 
              count += @runtimes_creators.synchronize { @runtimes_creators.size }
            end
            count if count < runtimes_size
          end
        end
        
        def create_runtime_when_needed
          @runtimes.synchronize do
            @runtimes_create.wait_until { may_create_runtime? }
          end
          create_runtime
          Thread.pass
        end
        
        def create_runtime
          creator = may_create_runtime?
          return unless creator
          @runtimes_creators.synchronize { @runtimes_creators << creator }
          puts "Creating runtime[#{creator}]"
          runtime = Util.benchmark do |header|
            runtime = org.jruby.Ruby.newInstance
            load_service = runtime.getLoadService
            load_service.getLoadPath.
              unshift File.expand_path('..', File.dirname(__FILE__))
            load_service.require 'java/nailgun'
            header.replace ["Created runtime[#{creator}]", runtime]
            runtime
          end
          @runtimes_creators.synchronize do 
            @runtimes_creators.delete(creator)
            @runtimes.synchronize do
              @runtimes << runtime
              @runtimes_ready.signal
            end
          end
        end

        def may_create_buildr?
          @buildrs.synchronize do 
            count = @buildrs.size
            if count < buildrs_size
              count += @buildrs_creators.synchronize { @buildrs_creators.size }
            end
            count if count < buildrs_size
          end
        end

        def create_buildr_when_needed
          @buildrs.synchronize do
            @buildrs_create.wait_until { may_create_buildr? }
          end
          Thread.pass while @runtime_creator.status == 'run'
          create_buildr
          Thread.pass
        end

        def create_buildr
          creator = may_create_buildr?
          return unless creator
          @buildrs_creators.synchronize { @buildrs_creators << creator }
          runtime = self.runtime
          puts "Loading buildr[#{creator}] on #{runtime} ..."
          Util.benchmark ["Loaded buildr[#{creator}] on #{runtime}"] do
            load_service = runtime.getLoadService
            load_service.require 'rubygems'
            load_service.require 'buildr'
          end
          @buildrs_creators.synchronize do
            @buildrs_creators.delete(creator)
            @buildrs.synchronize do
              @buildrs << runtime 
              @buildrs_ready.signal
            end
          end
        end
        
      end # BuildrFactory
      
      class BuildrServer < com.martiansoftware.nailgun.NGServer
        
        attr_reader :buildr_factory

        def initialize(host = 'localhost', port = 2113, buildr_factory = nil)
          super(java.net.InetAddress.get_by_name(host), port)
          @buildr_factory = buildr_factory
          @host, @port = host, port
        end

        def runtime
          JRuby.runtime
        end

        def to_ruby
          org.jruby.javasupport.JavaEmbedUtils.javaToRuby(runtime, java_object)
        end

        def start_server
          self.allow_nails_by_class_name = false

          BuildrNail::Main.nail = BuildrNail.new
          self.default_nail_class = BuildrNail::Main
          buildr_factory.start
          
          @thread = java.lang.Thread.new(self)
          @thread.setName(to_s)
          @thread.start
          
          sleep 1 while getPort == 0
          puts "#{self} Started."
        end

        def stop_server
          buildr_factory.stop
          @thread.kill
        end

        def to_s
          "BuildrServer(" <<
            [Rake.application.version, @host, @port].join(", ") <<
            ")"
        end
      end # class BuildrServer

    end # Nailgun boot
    
    namespace do
      tmp = lambda { |*files| File.join(Dir.tmpdir, "nailgun", *files) }
      dist_zip = Buildr.download(tmp[NAME + ".zip"] => URL)
      dist_dir = Buildr.unzip(tmp[NAME] => dist_zip)
      
      if File.exist?(File.join(home, NAME + ".jar"))
        ng_jar = file(File.join(home, NAME + ".jar"))
      else
        ng_jar = file(tmp[NAME, NAME, NAME+".jar"] => dist_dir)
      end
      
      self.artifact = Buildr.artifact(ARTIFACT_SPEC).from(ng_jar)
      
      compiled_bin = tmp[NAME, NAME, 'ng']
      compiled_bin << '.exe' if Config::CONFIG['host_os'] =~ /mswin/i
      compiled_bin = file(compiled_bin => dist_dir.target) do |task|
        unless task.to_s.pathmap('%x') == '.exe'
          Dir.chdir(task.to_s.pathmap('%d')) do
            puts "Compiling #{task.to_s}"
            system('make', task.to_s.pathmap('%f')) or
              fail "Nailgun binary compilation failed."
          end
        end
      end

      installed_bin = file(File.join(home, 
          compiled_bin.to_s.pathmap('%f')) => compiled_bin) do |task|
        mkpath task.to_s.pathmap('%d'), :verbose => false
        cp compiled_bin.to_s, task.to_s, :verbose => false
      end

      task :boot => artifact do |task|
        if $nailgun_server
          raise "Already nunning on Nailgun server: #{$nailgun_server}"
        end
        tasks = Rake.application.instance_eval { @top_level_tasks.dup }
        tasks.delete_if do |t| 
          t =~ /^(buildr:initialize|(ng|nailgun):.+)$/
        end
        unless tasks.empty?
          raise "Don't specify more targets when starting Nailgun server"
        end
        boot
      end
      
      task :start => [installed_bin, :boot] do
        factory = BuildrFactory.new(buildr_queue_size, jruby_queue_size)
        $nailgun_server = BuildrServer.new(server, port, factory)
        puts "Starting #{$nailgun_server}"
        $nailgun_server.start_server
        win = Config::CONFIG['host_os'] =~ /mswin/i
        puts <<-NOTICE


        Buildr server has been started, to use it execute 
          #{installed_bin.to_s}

        You may want to add the containing directory to your PATH
        variable:

          #{win ?
        "> set PATH=%PATH%;#{installed_bin.to_s.pathmap("%d")}" :
        "$ export PATH=${PATH}:#{installed_bin.to_s.pathmap("%d")}"
         }

         To display Nailgun related help, execute the command:
             ``ng ng:help''

         To get an overview of Nailgun tasks, execute the command:
             ``ng ng:tasks''

         Runtime for #{Rake.application.buildfile} has been cached
         and will be used by default when ``#{installed_bin.to_s.pathmap("%f")}'' is invoked
         from a directory inside of #{installed_bin.to_s.pathmap("%d")}
        NOTICE
      end

      task :help do 
        puts Rake.application.nailgun_help
      end

      task :tasks do 
        puts Rake.application.nailgun_tasks
      end
    end # namespace :nailgun
    
  end # module Nailgun
  
end
