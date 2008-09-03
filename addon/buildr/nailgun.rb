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

require 'benchmark'
require 'jruby'
require 'monitor'
require 'ostruct'
require 'rbconfig'
require 'thread'
require 'buildr/core/application_cli'

module Buildr #:nodoc:

  module Nailgun

    extend self
    
    attr_reader :ng
    @ng ||= OpenStruct.new

    VERSION = '0.7.1'
    NAME = "nailgun-#{VERSION}"
    URL = "http://downloads.sourceforge.net/nailgun/#{NAME}.zip"
    ARTIFACT_SPEC = "com.martiansoftware:nailgun:jar:#{VERSION}"

    # Paths used to initialize a buildr runtime
    BUILDR_PATHS = [File.expand_path('../', File.dirname(__FILE__)),
                    File.expand_path('../../lib', File.dirname(__FILE__))]

    private
    
    # Returns the path to JRUBY_HOME.
    def jruby_home
      ENV['JRUBY_HOME'] || Config::CONFIG['prefix']
    end
    
    # Returns the path to NAILGUN_HOME.
    def nailgun_home
      ENV['NAILGUN_HOME'] || File.expand_path('tool/nailgun', jruby_home)
    end

    def tmp_path(*paths)
      File.join(Dir.tmpdir, 'nailgun', *paths)
    end

    file_tasks = lambda do
      
      dist_zip = Buildr.download(tmp_path(NAME + '.zip') => URL)
      dist_dir = Buildr.unzip(tmp_path(NAME) => dist_zip)
      
      nailgun_jar = file(tmp_path(NAME, NAME, NAME + '.jar'))
      ng.artifact = Buildr.artifact(ARTIFACT_SPEC).from(nailgun_jar)
      unless File.exist?(nailgun_jar.to_s)
        nailgun_jar.enhance [dist_dir]
      end
      
      compiled_bin = file(tmp_path(NAME, NAME, 'ng' + Config::CONFIG['EXEEXT']) => dist_dir.target) do |task|
        unless task.to_s.pathmap('%x') == '.exe'
          Dir.chdir(task.to_s.pathmap('%d')) do
            info "Compiling #{task.to_s}"
            system('make', task.to_s.pathmap('%f')) or
              fail "Nailgun binary compilation failed."
          end
        end
      end
      
      ng.installed_bin = file(File.expand_path(compiled_bin.to_s.pathmap('%f'), nailgun_home) => compiled_bin) do |task|
        mkpath task.to_s.pathmap('%d'), :verbose => false
        cp compiled_bin.to_s, task.to_s, :verbose => false
      end
      
    end # file_tasks

    server_tasks = lambda do 

      task('start', :port, :iface, :queue_size) do |task, args|
        
        [ng.installed_bin, ng.artifact].map(&:invoke)
        
        iface = args[:iface].to_s.empty? ? '127.0.0.1' : args[:iface]
        port  = args[:port].to_s.empty? ? 2113 : args[:port].to_i
        queue_size = args[:queue_size].to_s.empty? ? 3 : args[:queue_size].to_i

        fail "Already running on Nailgun server: #{ng.server || ng.nail}" if ng.server || ng.client
        
        info 'Booting Buildr nailgun server...'
        top_level = Buildr.application.instance_eval { @top_level_tasks.dup }
        top_level.delete_if { |t| t[/nailgun/] }
        unless top_level.empty?
          raise 'Don\'t specify more targets when starting Nailgun server: #{top_level}'
        end
        ng.server_setup.call

        factory = RuntimeFactory.new(queue_size, queue_size)
        ng.server = NGServer.new(iface, port, factory)

        ng.server.start
      end

      task('help') do
        info "HELP"
      end

      task('list') do
        info "HELLO"
      end
      
    end # server_tasks

    client_tasks = lambda do


    end # client_tasks

    # Load java classes on server side.
    ng.server_setup = lambda do 

      module Util
        include Buildr::Util
      end

      Util.add_to_sysloader ng.artifact.to_s
      Util.add_to_sysloader File.dirname(__FILE__)

      class NGClient
        include org.apache.buildr.BuildrNail
        include Client
      end

      class NGServer < com.martiansoftware.nailgun.NGServer
        include Server
      end

    end # server_setup
    
    module Util
      extend self
      
      def add_to_sysloader(path)
        sysloader = java.lang.ClassLoader.getSystemClassLoader
        add_url_method = java.lang.Class.forName('java.net.URLClassLoader').
          getDeclaredMethod('addURL', [java.net.URL.java_class].to_java(java.lang.Class))
        add_url_method.setAccessible(true)
        add_url_method.invoke(sysloader, [java.io.File.new(path).toURI.toURL].to_java(java.net.URL))
      end

      def benchmark(action = ['Completed'], verbose = true)
        result = nil
        times = Benchmark.measure do
          result = yield(action)
        end
        if verbose
          real = []
          real << ("%ih" % (times.real / 3600)) if times.real >= 3600
          real << ("%im" % ((times.real / 60) % 60)) if times.real >= 60
          real << ("%.3fs" % (times.real % 60))
          trace "#{[action].flatten.join(' ')} in #{real.join}"
        end
        result
      end

      def find_file(pwd, candidates, nosearch=false)
        candidates = [candidates].flatten
        buildfile = candidates.find { |c| File.file?(File.expand_path(c, pwd)) }
        return File.expand_path(buildfile, pwd) if buildfile
        return nil if nosearch
        updir = File.dirname(pwd)
        return nil if File.expand_path(updir) == File.expand_path(pwd)
        find_file(updir, candidates)
      end

      def exception_handling(raise_again = true, show_error = true)
        begin
          yield
        rescue => e
          if show_error
            error "#{e.backtrace.shift}: #{e.message}"
            e.backtrace.each { |i| error "\tfrom #{i}" }
          end
          raise if raise_again
        end
      end

      # invoke a java constructor
      def ctor(on_class, *args)
        parameters = []
        classes = []
        args.each do |obj|
          case obj
          when nil
            classes.push(nil)
            parameters.push(nil)
          when Hash
            vclass = obj.keys.first
            value = obj[vclass]
            classes.push(vclass.java_class)
            parameters.push(value)
          else
            parameters.push obj
            classes.push obj.java_class
          end
        end
        on_class = [on_class.java_class].to_java(java.lang.Class)[0]
        ctor = on_class.getDeclaredConstructor(classes.to_java(java.lang.Class))
        ctor.setAccessible(true)
        ctor.newInstance(parameters.to_java(java.lang.Object))
      end

      def on_runtime(runtime, *args, &block)
        raise_error = lambda do |cls, msg, trace|
          raise RuntimeError.new(cls + ": "+ msg.to_s).tap { |e| e.set_backtrace(trace.map(&:to_s)) }
        end
        executor = runtime.object.const_get(:Module).new do
          extend self
          def runtime_exec(*args, &prc)
            define_method(:runtime_exec, &prc)
            runtime_exec(*args)
          rescue => e
            [:error, e.class.name, e.message, e.backtrace]
          end
        end
        result = executor.runtime_exec(*args, &block)
        raise_error.call(*result[1..-1]) if result.kind_of?(Array) && result.first == :error
        result
      end

      def set_stdio(runtime, dev)
        set_global = lambda do |global, constant, stream|
          runtime.global_variables.set(global, stream)
          runtime.object.send(:remove_const, constant)
          runtime.object.send(:const_set, constant, stream)
        end
        stdin  = runtime.global_variables.get('$stdin')
        stdout = runtime.global_variables.get('$stdout')
        stderr = runtime.global_variables.get('$stderr')
        #stdin.close; stdout.close; stderr.close;
        output = Util.ctor(org.jruby.RubyIO, runtime, java.io.OutputStream => dev.out)
        error = Util.ctor(org.jruby.RubyIO, runtime, java.io.OutputStream => dev.err)
        input = Util.ctor(org.jruby.RubyIO, runtime, java.io.InputStream => dev.in)
        #stdin.reopen(input, 'r') # not working on jruby, :(
        #stdout.reopen(output, 'w')
        #stderr.reopen(error, 'w')
        set_global.call('$stdin', 'STDIN', input)
        set_global.call('$stdout', 'STDOUT', output)
        set_global.call('$stderr', 'STDERR', error)
      end

    end # module Util

    class FieldAccessor
      def initialize(obj, clazz = nil)
        @obj = obj
        clazz ||= obj.class
        @cls = [clazz.java_class].to_java(java.lang.Class)[0]
      end

      def [](name)
        field = @cls.getDeclaredField(name.to_s)
        field.setAccessible(true)
        field.get(@obj)
      end
      
      def []=(name, value)
        field = @cls.getDeclaredField(name.to_s)
        field.setAccessible(true)
        field.set(@obj, value)
      end
      
      def method_missing(name, value =nil)
        if name.to_s =~ /=$/
          self[name.to_s.chomp('=')] = value
        else
          self[name]
        end
      end
    end

    module NailMethods
        
      def self.extend_object(obj)
        super
        (class << obj; self; end).module_eval do
          alias_method :pwd, :getWorkingDirectory
          alias_method :server, :getNGServer
        end
      end
      
      def argv
        [command] + args
      end

      def attach_runtime(runtime)
        runtime.extend RuntimeMixin
        runtime.evalScriptlet %q{
          require 'ostruct'
          module Buildr
            module Nailgun
              extend self
              attr_reader :ng
              @ng = OpenStruct.new
            end
          end
        }
        runtime.Buildr::Nailgun.ng.nail = self
        runtime.load_service.require __FILE__
        runtime
      end
      private :attach_runtime
      
      def jruby
        @jruby ||= server.runtime_factory.new_jruby.tap do |runtime|
          attach_runtime(runtime)
        end
      end
      
      def buildr
        @buildr ||= server.runtime_factory.new_buildr.tap do |runtime|
          attach_runtime(runtime)
        end
      end
      
      def options
        @options ||= OpenStruct.new
      end
      
    end # NailMethods

    module RuntimeMixin
      def Buildr
        object.const_get(:Buildr)
      end
    end
    
    module AppMixin        
      def load_tasks
        trace "Not loading tasks again"
      end
      
      def load_buildfile
        trace "Not loading buildfile again"
      end        
    end

    module Client

      class << self
        include Buildr::CommandLineInterface

        def options
          Nailgun.ng.nail.options
        end

        def rakefiles
          Nailgun.ng.nail.options.rakefiles
        end

        def requires
          Nailgun.ng.nail.options.requires
        end
        
        def help
          super
          puts 
          puts 'To get a summary of Nailgun features use'
          puts '  nailgun:help'        
        end

        def version
          puts super
        end

        def do_option(opt, value)
          case opt
          when '--help'
            options.exit = :help
          when '--version'
            options.exit = :version
          when '--nosearch'
            options.nosearch = true
          else
            super
          end
        end

        def sBuildr
          Nailgun.ng.nail.server.runtime.object.const_get(:Buildr)
        end
        
        def attach_runtime
          nail = Nailgun.ng.nail
          ARGV.replace nail.argv
          Dir.chdir nail.pwd
          nail.env.each { |k, v| ENV[k.to_s] = v.to_s }
          
          Buildr.const_set(:VERSION, sBuildr::VERSION) unless Buildr.const_defined?(:VERSION)
          nail.options.rakefiles = sBuildr::Application::DEFAULT_BUILDFILES.dup
          nail.options.requires = []
        end
        
        def client(runtime, nail, &block)
          Util.set_stdio(runtime, nail)
          nailgun_module = runtime.Buildr::Nailgun
          nailgun_module.ng.nail = nail
          nailgun_module::Client.attach_runtime
          nailgun_module::Client.instance_eval(&block)
        end
      end

      def main(nail)
        nail.extend NailMethods
        info "Got connection from #{nail.pwd}"

        Client.client(nail.jruby, nail) do
          
          parse_options
          if options.exit
            send(options.exit)
            nail.exit(0)
          end

          if options.project && File.directory?(options.project)
            Dir.chdir(options.project)
          end
          
          bf = Util.find_file(Dir.pwd, options.rakefiles, options.nosearch)
          unless bf
            nail.out.println "No buildfile found at #{Dir.pwd}"
            nail.exit(0)
          end
          
          rt = nail.server.cached_runtimes[bf]
          old_stamp = nail.server.cached_stamps[bf] || Rake::EARLY
          new_stamp = rt ? rt.Buildr.application.buildfile.timestamp : Rake::EARLY
          
          if rt.nil? || new_stamp > old_stamp
            rt = nail.buildr
            app = rt.Buildr.application
          else
            app = rt.Buildr.application.extend AppMixin
            app.lookup('buildr:initialize').instance_eval do 
              @already_invoked = false
              @actions = []
            end
            app.instance_eval do
              @tasks.values.each do |task|
                is_project = rt.Buildr::Project.instance_variable_get(:@projects).key?(task.name)
                task.instance_variable_set(:@already_invoked, false) unless is_project
              end
            end
          end

          app.instance_eval do
            @original_dir = nail.pwd
          end

          Client.client(rt, nail) do
            Util.exception_handling do
              begin
                app.parse_options
                app.collect_tasks
                app.run
              rescue SystemExit => e
                nail.exit(1)
              end
            end
          end

          nail.server.cache(rt, app.buildfile)
        end
      end
      
    end # class Client

    module Server

      attr_reader :runtime_factory
      attr_reader :cached_runtimes
      attr_reader :cached_stamps

      def initialize(host = 'localhost', port = 2113, buildr_factory = nil)
        super(java.net.InetAddress.get_by_name(host), port)
        @cached_runtimes = {}
        @cached_stamps = {}
        cache(runtime, Buildr.application.buildfile)
        @runtime_factory = buildr_factory
        @host, @port = host, port
      end

      def cache(runtime, buildfile)
        cached_runtimes[buildfile.to_s] = runtime
        cached_stamps[buildfile.to_s] = buildfile.timestamp
      end

      def runtime
        JRuby.runtime.extend RuntimeMixin
      end

      def start
        self.allow_nails_by_class_name = false
        
        NGClient::Main.nail = NGClient.new
        self.default_nail_class = NGClient::Main
        runtime_factory.start
        
        @thread = java.lang.Thread.new(self)
        @thread.setName(to_s)
        @thread.start
        
        sleep 1 while getPort == 0
        info "#{self} Started."
      end
      
      def stop
        runtime_factory.stop
        @thread.kill
      end

      def to_s
        self.class.name+'('+[Buildr.application.version, @host, @port].join(', ')+')'
      end
    end # module Server
    
    class RuntimeFactory
      
      attr_accessor :buildrs_size, :jrubys_size
      
      def initialize(buildrs_size = 1, jrubys_size = nil)
        # jrubys_size ||= buildrs_size
        @buildrs_size = buildrs_size < 1 ? 1 : buildrs_size
        # @jrubys_size = jrubys_size < 1 ? 1 : jrubys_size

        @buildrs = [].extend(MonitorMixin)
        @buildrs_ready = @buildrs.new_cond
        @buildrs_needed = @buildrs.new_cond
        
        @buildrs_creators = [].extend(MonitorMixin)

        # @jrubys = [].extend(MonitorMixin)
        # @jrubys_ready = @jrubys.new_cond
        # @jrubys_needed = @jrubys.new_cond
        
        # @jrubys_creators = [].extend(MonitorMixin)
      end
      
      def new_buildr
        get(:buildr)
      end

      def new_jruby(&block)
        # get(:jruby)
        create_jruby(0, &block)
      end

      def start
        trace "Starting Buildr runtime factory"
        # @jruby_creator = Thread.new { loop { create :jruby } }
        # @jruby_creator.priority = -2
        @buildr_creator = Thread.new { loop { create :buildr } }
        @buildr_creator.priority = 1
      end

      def stop
        @buildr_creator.kill if @buildr_creator
        # @jruby_creator.kill if @jruby_creator
      end

      private
      def get(thing)
        collection = instance_variable_get("@#{thing}s")
        needs = instance_variable_get("@#{thing}s_needed")
        ready = instance_variable_get("@#{thing}s_ready")
        result = nil
        collection.synchronize do 
          if collection.empty?
            trace "no #{thing} available, ask to create more"
            needs.broadcast
            trace "should be creating #{thing}"
            ready.wait_while { collection.empty? }
          end
          trace "Getting my #{thing}"
          result = collection.shift
          trace "would need more #{thing}s"
          needs.broadcast
          trace "got my #{thing}: #{result.inspect}"
          Thread.pass
        end
        trace "returning #{result.inspect}"
        result
      end

      def create(thing, *args, &block)
        Util.exception_handling do
          creator = needed(thing)
          collection = instance_variable_get("@#{thing}s")
          ready = instance_variable_get("@#{thing}s_ready")
          needs = instance_variable_get("@#{thing}s_needed")
          unless creator
            collection.synchronize do
              trace "awake those wanting a #{thing}"
              ready.broadcast
              Thread.pass
              trace "wait until more #{thing}s are needed"
              # needs.wait(1); return
              needs.wait_until { creator = needed(thing) }
            end
          end
          trace "About to create #{thing} # #{creator}"
          method = "create_#{thing}"
          creators = instance_variable_get("@#{thing}s_creators")
          trace "registering creator for #{thing} #{creator}"
          creators.synchronize { creators << creator }
          result = send(method, creator, *args, &block)
          trace "created #{thing}[#{creator}] => #{result.inspect}"
          creators.synchronize do 
            trace "unregistering creator for #{thing} #{creator}"
            creators.delete(creator)
            collection.synchronize do
              trace "adding object on queue for #{thing} #{creator}"
              collection << result
            end
          end
        end
      end
      
      def needed(thing)
        collection = instance_variable_get("@#{thing}s")
        creators = instance_variable_get("@#{thing}s_creators")
        size = instance_variable_get("@#{thing}s_size")
        collection.synchronize do
          count = collection.size
          if count < size
            count += creators.synchronize { creators.size }
          end
          count if count < size
        end
      end
      
      def create_jruby(creator, &block)
        Util.exception_handling do
          trace "Creating jruby[#{creator}]"
          Util.benchmark do |header|
            cfg = org.jruby.RubyInstanceConfig.new
            yield cfg if block_given?
            jruby = org.jruby.Ruby.newInstance(cfg)
            jruby.load_service.load_path.unshift *BUILDR_PATHS
            header.replace ["Created jruby[#{creator}]", jruby]
            jruby
          end
        end
      end

      def create_buildr(creator)
        Util.exception_handling do 
          trace "Obtaining jruby to load buildr[#{creator}] on it"
          jruby = new_jruby
          trace "Loading buildr[#{creator}] on #{jruby} ..."
          Util.benchmark ["Loaded buildr[#{creator}] on #{jruby}"] do
            load_service = jruby.load_service
            load_service.require 'rubygems'
            load_service.require 'buildr'
          end
          jruby
        end
      end
      
    end # RuntimeFactory

    if Buildr.respond_to?(:application) && ng.nail.nil?
      Buildr.application.in_namespace(:nailgun, &file_tasks)
      Buildr.application.in_namespace(:nailgun, &server_tasks)
    end

  end # module Nailgun
  
end
