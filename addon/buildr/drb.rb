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


require 'drb/drb'


module Buildr

  # This addon allows you start a DRb server hosting a buildfile, so that
  # you can later invoke tasks on it without having to load
  # the complete buildr runtime again.
  # 
  # Usage:
  #   
  #   buildr -r buildr/drb drb:start
  #
  # Once the server has been started you can invoke tasks using a simple script:
  # 
  #   #!/usr/bin/env ruby
  #   require 'rubygems'
  #   require 'buildr'
  #   require 'buildr/drb'
  #   Buildr::DRbApplication.run
  #
  # Save this script as 'dbuildr', make it executable and use it to invoke tasks.
  #
  #   dbuildr clean compile
  #
  # The 'dbuildr' will start the server if there isn't one already running.
  # Subsequent calls to dbuildr will act as the client and invoke the tasks you
  # provide to the server.
  # If the buildfile has been modified it will be reloaded on the server app.
  #
  # JRuby users can use a nailgun client to invoke tasks as fast as possible
  # without having to incur JVM startup time.
  # See the documentation for buildr/nailgun.
  module DRbApplication
    
    port = ENV['DRB_PORT'] || 2111
    PORT = port.to_i

    class SavedTask #:nodoc:
      attr_reader :original, :prerequisites, :actions
      
      def initialize(original)
        @original = original.dup
        @prerequisites = original.send(:prerequisites).map(&:to_s)
        @actions = original.instance_eval { @actions }.clone
      end
      
      def name
        original.name
      end
      
      def define!
        original.class.send(:define_task, original.name => prerequisites).tap do |task|
          task.comment = original.comment
          actions.each { |action| task.enhance &action }
        end
      end
    end # SavedTask

    class Snapshot #:nodoc:
      
      attr_accessor :projects, :tasks, :rules, :layout
      
      # save the tasks,rules,layout defined by buildr
      def initialize
        @projects = Project.instance_variable_get(:@projects) || {}
        @tasks = Buildr.application.tasks.inject({}) do |hash, original|
          unless projects.key? original.name # don't save project definitions
            hash.update original.name => SavedTask.new(original)
          end
          hash
        end
        @rules = Buildr.application.instance_variable_get(:@rules)
        @layout = Layout.default.clone
      end
      
    end # Snapshot

    # The tasks,rules,layout defined by buildr
    # before loading any project
    @original = Snapshot.new

    class << self
      
      attr_accessor :original, :snapshot

      def run
        begin
          client = connect
        rescue DRb::DRbConnError => e
          run_server!
        else
          run_client(client)
        end
      end

      def client_uri
        "druby://:#{PORT + 1}"
      end

      def remote_run(cfg)
        with_config(cfg) { Buildr.application.remote_run(self) }
      rescue => e
        cfg[:err].puts e.message
        e.backtrace.each { |b| cfg[:err].puts "\tfrom #{b}" }
        raise e
      end

      def save_snapshot(app)
        app.extend self
        if app.instance_eval { @rakefile }
          @snapshot = self::Snapshot.new
          app.buildfile_reloaded!
        end
      end

    private

      def server_uri
        "druby://:#{PORT}"
      end
      
      def connect
        buildr = DRbObject.new(nil, server_uri)
        uri = buildr.client_uri # obtain our uri from the server
        DRb.start_service(uri)
        buildr
      end

      def run_client(client)
        client.remote_run :dir => Dir.pwd, :argv => ARGV,
                          :in  => $stdin, :out => $stdout, :err => $stderr
      end

      def run_server
        save_snapshot(Buildr.application)
        DRb.start_service(server_uri, self)
        puts "#{self} waiting on #{server_uri}"
      end

      def run_server!
        if RUBY_PLATFORM[/java/]
          require 'buildr/nailgun'
          info ''
          info 'Running in JRuby, a nailgun server will be started so that'
          info 'you can use your nailgun client to invoke buildr tasks: '
          info ''
          info '  '+Nailgun.installed_bin.to_s
          info ''
          Buildr.application['nailgun:start'].invoke
        else
          run_server
        end
        DRb.thread.join
      end
      
      def with_config(remote)
        @invoked = true
        set = lambda do |env|
          ARGV.replace env[:argv]
          $stdin, $stdout, $stderr = env.values_at(:in, :out, :err)
          Buildr.application.instance_variable_set :@original_dir, env[:dir]
        end
        original = { 
          :dir => Buildr.application.instance_variable_get(:@original_dir), 
          :argv => ARGV, :in => $stdin, :out => $stdout, :err => $stderr
        }
        begin
          set[remote]
          yield
        ensure
          set[original]
        end
      end

    end # class << DRbApplication

    def remote_run(server)
      init 'Distributed Buildr'
      if @rakefile
        if buildfile_needs_reload?
          reload_buildfile(server.original)
          server.save_snapshot(self)
        else
          clear_invoked_tasks(server.snapshot || server.original)
        end
      else
        reload_buildfile(server.original)
        server.save_snapshot(self)
      end
      top_level
    end

    def buildfile_reloaded!
      @last_loaded = buildfile.timestamp if @rakefile
    end

  private
    
    def buildfile_needs_reload?
      !@last_loaded || @last_loaded < buildfile.timestamp
    end

    def reload_buildfile(snapshot)
      clear_for_reload(snapshot)
      load_buildfile
      buildfile_reloaded!
    end

    def clear_for_reload(snapshot)
      Project.clear
      @tasks = {}
      snapshot.tasks.each_pair { |name, saved| saved.define! }
      @rules = snapshot.rules.clone
      Layout.default = snapshot.layout.clone
    end

    def clear_invoked_tasks(snapshot)
      @tasks = {}
      snapshot.tasks.each_pair { |name, saved| saved.define! }
    end

    namespace(:drb) { task('start') { run_server! } }
    
  end # DRbApplication

end

