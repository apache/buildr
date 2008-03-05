module Buildr
  
  # To start the nailgun server run the ng:start task, this will
  # download, compile and installed nailgun if needed, afterwards
  # it will start the nailgun server.
  module Nailgun 
    VERSION = '0.7.1'
    NAME = "nailgun-#{VERSION}"
    URL = "http://downloads.sourceforge.net/nailgun/#{NAME}.zip"
    ARTIFACT_SPEC = "com.martiansoftware:nailgun:jar:#{VERSION}"

    class << self
      attr_accessor :artifact
      attr_accessor :iface, :port, :runtime_pool_size
      attr_accessor :jruby_home, :home
    end

    self.jruby_home = if PLATFORM =~ /java/
                        Config::CONFIG['prefix']
                      else
                        ENV['JRUBY_HOME'] || File.join(ENV['HOME'], '.jruby')
                      end
    self.home = ENV['NAILGUN_HOME'] || File.join(jruby_home, 'tool', 'nailgun')
    self.iface = 'localhost'
    self.port = 2113
    self.runtime_pool_size = 0
        
    namespace :nailgun do
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

      task :boot => artifact do
        if $nailgun_server
          raise "Already nunning on Nailgun server: #{$nailgun_server}"
        end
        BOOT.call
      end
      
      task :start => [installed_bin, :boot] do
        factory = BuildrFactory.new(runtime_pool_size)
        $nailgun_server = BuildrServer.new(iface, port, factory)
        puts "Starting #{$nailgun_server}"
        $nailgun_server.start_server
      end
    end # namespace :nailgun

    
  end # module Nailgun

  Nailgun::BOOT = lambda do
    require 'jruby'
    
    class Application
      def buildfile(dir = nil, candidates = nil)
        Nailgun::Util.find_buildfile(dir || Dir.pwd, candidates || @rakefiles)
      end

      def clear_invoked
        tasks.each { |t| t.instance_variable_set(:@already_invoked, false) }
      end
    end

    module Nailgun
      class ::ConcreteJavaProxy
        def self.jclass(name = nil)
          name ||= self.java_class.name
          Util.class_for_name(name)
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
              cls = Util.proxy_class(cls) if String == cls
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
        extend self

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

        def find_buildfile(pwd, candidates)
          buildfile = candidates.find { |c| File.file?(File.join(pwd, c)) }
          return File.expand_path(buildfile, pwd) if buildfile
          updir = File.dirname(pwd)
          return nil if File.expand_path(updir) == File.expand_path(pwd)
          find_buildfile(updir, candidates)
        end

        def benchmark(action = 'Completed', verbose = true)
          result = nil
          times = Benchmark.measure do
            result = yield
          end
          if verbose
            real = []
            real << ("%ih" % (times.real / 3600)) if times.real >= 3600
            real << ("%im" % ((times.real / 60) % 60)) if times.real >= 60
            real << ("%.3fs" % (times.real % 60))
            puts "#{action} in #{real.join}"
          end
          result
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
            p nail.in
            input  = RubyIO.jnew(runtime, java.lang.System.in => java.io.InputStream)
            output = RubyIO.jnew(runtime, nail.out => java.io.OutputStream)
            error = RubyIO.jnew(runtime, nail.err => java.io.OutputStream)
            #stdin.reopen(input, 'r') # not working on jruby :(
            #set_in.call(input)
            stdout.reopen(output)
            stderr.reopen(error)
            result = yield
          ensure
            input  = RubyIO.jnew(runtime, java.lang.System.in => java.io.InputStream)
            output = RubyIO.jnew(runtime, java.lang.System.out => java.io.OutputStream)
            error = RubyIO.jnew(runtime, java.lang.System.err => java.io.OutputStream)
            #set_in.call(input)
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
        end

        def run(nail)
          nail.assert_loopback_client
          nail.out.println "Obtaining Buildr runtime from #{nail.getNGServer}"
          pwd = nail.working_directory
          env = nail.env
          argv = [nail.command] + nail.args.map(&:to_s)

          ARGV.replace(argv)
          Util.redirect_stdio(JRuby.runtime, nail) do
            Util.benchmark 'Local Buildr completed' do 
              Rake.application.instance_eval do
                clear_invoked
                opts = GetoptLong.new(*command_line_options)
                opts.each { |opt, value| do_option(opt, value) }
                collect_tasks
                @top_level_tasks.delete('buildr:initialize')
                top_level
              end
            end
          end
          
        end

        private

      end # class BuildrNail

      class BuildrFactory
        require 'thread'
        require 'monitor'
        
        attr_reader :work_queue_size

        def initialize(size)
          @work_queue = [].extend(MonitorMixin)
          @work_queue_size = size
          @ready_cond = @work_queue.new_cond
          @workers = [].extend(MonitorMixin)
        end

        def obtain
          @work_queue.synchronize do 
            @ready_cond.wait_while { @work_queue.empty? }
            @work_queue.shift
          end
        end

        def start
          puts "Starting Buildr runtime queue"
          @thread = Thread.new do
            create_if_needed
            sleep 10
            loop { create_if_needed }
          end
        end

        def stop
          @thread.kill if @thread
        end

        private
        def configure_runtime(runtime)
          load_service = runtime.getLoadService
          load_service.add_path File.expand_path('..', File.dirname(__FILE__))
          load_service.require 'rubygems'
          load_service.require 'buildr'
        end

        def create_runtime
          @workers.synchronize { @workers << Thread.current }
          puts "Creating new Buildr runtime"
          cfg = org.jruby.RubyInstanceConfig.new
          cfg.input = java.lang.System.in
          cfg.output = java.lang.System.out
          cfg.error = java.lang.System.err
          cfg.current_directory Dir.pwd
          runtime = nil
          times = Benchmark.measure do 
            runtime = org.jruby.Ruby.new_instance(cfg)
            configure_runtime(runtime)
          end
          real = []
          real << ("%ih" % (times.real / 3600)) if times.real >= 3600
          real << ("%im" % ((times.real / 60) % 60)) if times.real >= 60
          real << ("%.3fs" % (times.real % 60))
          puts "Buildr runtime #{runtime} created in #{real.join}"

          @workers.synchronize do 
            @workers.delete(Thread.current)
            @work_queue.synchronize { @work_queue << runtime }
          end
          
          create_if_needed
          @ready_cond.signal
        end

        def create_if_needed
          return unless may_create?
          Thread.new { create_runtime }
        end
        
        def may_create?
          @workers.synchronize do
            workers = @workers.size
            worked = @work_queue.synchronize { @work_queue.size }
            (workers + worked) < work_queue_size
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
        
        def start_server
          self.allow_nails_by_class_name = false

          BuildrNail::Main.nail = BuildrNail.new
          self.default_nail_class = BuildrNail::Main
          buildr_factory.start
          
          t = java.lang.Thread.new(self)
          t.setName(to_s)
          t.start
          
          sleep 1 while getPort == 0
          puts "#{self} Started."
        end

        def to_s
          "BuildrServer(" <<
            [Rake.application.buildfile, @host, @port].join(", ") <<
            ")"
        end
      end # class BuildrServer
      
    end # module Nailgun
  end # Nailgun::Boot
end
