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

    # save the tasks,rules,layout defined by buildr
    # based on the code from the sandbox
    @tasks = Buildr.application.tasks.collect do |original|
      prerequisites = original.send(:prerequisites).map(&:to_s)
      actions = original.instance_eval { @actions }.clone
      lambda do
        original.class.send(:define_task, original.name=>prerequisites).tap do |task|
          task.comment = original.comment
          actions.each { |action| task.enhance &action }
        end
      end
    end
    @rules = Buildr.application.instance_variable_get(:@rules)
    @layout = Layout.default.clone
    
    class << self
      attr_accessor :tasks, :rules, :layout

      def server_uri
        "druby://:#{PORT}"
      end
      
      def client_uri
        "druby://:#{PORT + 1}"
      end

      def run
        begin
          run_client
        rescue DRb::DRbConnError
          run_server!
        end
      end

      def run_client
        buildr = DRbObject.new(nil, server_uri)
        buildr.remote_ping # test if the server is running
        DRb.start_service(client_uri)
        buildr.remote_run :dir => Dir.pwd, 
                          :in  => $stdin, 
                          :out => $stdout, 
                          :err => $stderr,
                          :argv => ARGV
      end

      def run_server
        Application.module_eval { include DRbApplication }
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
        set = lambda do |env|
          ARGV.replace env[:argv]
          $stdin, $stdout, $stderr = env.values_at(:in, :out, :err)
          Buildr.application.instance_variable_set :@original_dir, env[:dir]
        end
        original = { 
          :dir => Buildr.application.instance_variable_get(:@original_dir), 
          :in => $stdin, 
          :out => $stdout, 
          :err => $stderr, 
          :argv => ARGV 
        }
        begin
          set[remote]
          yield
        ensure
          set[original]
        end
      end

      def remote_run(cfg)
        with_config(cfg) { Buildr.application.remote_run }
      rescue => e
        puts e
      end

    end # class << DRbApplication

    def remote_run
      init 'Distributed Buildr'
      if @rakefile
        if !@last_loaded || buildfile.timestamp > @last_loaded
          # buildfile updated, need to reload
          Project.clear
          @tasks = {}
          DRbApplication.tasks.each { |block| block.call }
          @rules = DRbApplication.rules.clone
          Layout.default = DRbApplication.layout.clone
          @last_loaded = buildfile.timestamp
          load_buildfile
        else
          clear_invoked_tasks
        end
      else
        load_buildfile
        @last_loaded = buildfile.timestamp
      end      
      top_level
    end

    def clear_invoked_tasks
      lookup('buildr:initialize').instance_eval do
        @already_invoked = true
        @actions = []
      end
      projects = Project.instance_variable_get(:@projects) || {}
      @tasks.each_pair do |name, task|
        is_project = projects.key?(task.name)
        task.instance_variable_set(:@already_invoked, false) unless is_project
      end
    end

    drb_tasks = lambda do
      task('start') { run_server! }
    end
    
    if Buildr.respond_to?(:application)
      Buildr.application.instance_eval do
        @rakefile = "" unless @rakefile
        in_namespace(:drb, &drb_tasks)
      end
    end
    
  end # DRbApplication

end

