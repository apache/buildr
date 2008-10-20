# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with this
# work for additional information regarding copyright ownership. The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.
 
 
require File.expand_path('../spec_helpers', File.dirname(__FILE__))
require 'stringio'
Sandbox.require_optional_extension 'buildr/drb'


describe Buildr::DRbApplication do 

  module DRbHelper 
    attr_accessor :app, :drb, :cfg

    def use_argv(*args)
      cfg.update :argv => args
    end

    def use_stdio(stdin = nil, stdout = nil, stderr = nil)
      stdin ||= StringIO.new
      stdout ||= StringIO.new
      stderr ||= StringIO.new
      cfg.update :in => stdin, :out => stdout, :err => stderr
    end
    
    def remote_run
      drb.remote_run(cfg)
    end

    def output
      cfg[:out].string
    end

    def write_buildfile(content = nil)
      write 'buildfile', content || <<-BF
          define('foo') do

            task('hello') do 
              $stdout.puts 'hi'
            end

            task('empty')

            task('no') do
              task('empty' => 'delete_me')
              task('empty') { $stout.puts 'no' }
            end

            task('delete_me') do
            end
          end
      BF
    end
  end

  include DRbHelper
  
  before(:each) do
    @cfg = {
      :dir => Dir.pwd, :argv => [],
      :in => $stdin, :out => $stdout, :err => $stderr
    }
    @drb = Buildr::DRbApplication.clone
    @app = Buildr.application.extend @drb
  end
  
  describe '.run' do
    it 'starts server if no server is running' do
      drb.should_receive(:connect).and_raise DRb::DRbConnError
      drb.should_receive(:run_server!)
      drb.should_not_receive(:run_client)
      drb.run
    end

    it 'connects to an already started server' do
      drb.should_receive(:connect).and_return "client"
      drb.should_receive(:run_client).with "client"
      drb.should_not_receive(:run_server!)
      drb.run
    end
  end

  describe '.remote_run' do
    
    describe 'stdout' do
      it 'is redirected to client' do 
        use_stdio
        Buildr.application.should_receive(:remote_run) do 
          $stdout.puts "HELLO"
        end
        remote_run
        output.should eql("HELLO\n")
      end
    end

    describe 'stderr' do 
      it 'is redirected to client' do
        use_stdio
        Buildr.application.should_receive(:remote_run) do 
          $stderr.puts "HELLO"
        end
        remote_run
        cfg[:err].string.should eql("HELLO\n")
      end
    end

    describe 'stdin' do
      it 'is redirected to client' do
        use_stdio
        cfg[:in].should_receive(:gets).and_return("HELLO\n")
        result = nil
        Buildr.application.should_receive(:remote_run) do 
          result = $stdin.gets
        end
        remote_run
        result.should eql("HELLO\n")
      end
    end

    describe 'server ARGV' do
      it 'is replaced with client argv' do
        use_argv 'hello'
        Buildr.application.should_receive(:remote_run) do 
          ARGV.should eql(['hello'])
        end
        remote_run
      end
    end

    describe 'without buildfile loaded' do
      before(:each) do
        app.instance_eval { @rakefile = nil }
        write_buildfile
      end
      
      it 'should load the buildfile' do
        app.should_receive(:top_level)
        lambda { remote_run }.should run_task('foo')
      end
    end

    describe 'with unmodified buildfile' do
      
      before(:each) do 
        write_buildfile
        app.options.rakelib = []
        app.send :load_buildfile
        app.send :buildfile_reloaded!
      end
      
      it 'should not reload the buildfile' do
        app.should_not_receive(:reload_buildfile)
        app.should_receive(:top_level)
        remote_run
      end

      it 'should invoke tasks specified by client' do
        times = 0
        task(:hello) { times += 1 }
        use_argv 'hello'
        2.times { remote_run }
        times.should eql(2)
      end

      it 'should not define projects again' do
        use_stdio
        use_argv 'foo:hello'
        lambda { 2.times { remote_run } }.should_not run_task('foo')
        output.should eql("hi\nhi\n")
      end
      
    end

    describe 'with modified buildfile' do
      
      before(:each) do 
        write_buildfile
        app.options.rakelib = []
        app.send :load_buildfile
        app.send :buildfile_reloaded!
        app.instance_eval { @last_loaded = Time.now - 10 }
        write_buildfile <<-BF
          define('foo') do
            task('hello') do 
              $stdout.puts 'bye'
            end
            task('empty')
            define('bar') do
              
            end
          end
        BF
      end

      it 'should reload the buildfile' do
        app.should_receive(:reload_buildfile)
        app.should_receive(:top_level)
        remote_run
      end

      it 'should redefine projects' do
        lambda { remote_run }.should run_tasks('foo', 'foo:bar')
      end

      it 'should remove tasks deleted from buildfile' do
        app.lookup('foo:delete_me').should_not be_nil
        remote_run
        app.lookup('foo:delete_me').should be_nil
      end
      
      it 'should restore tasks actions' do
        actions = app.lookup('foo:empty').instance_eval { @actions }
        actions.should be_empty # no action
        app.lookup('foo:no').invoke # enhance the empty task
        actions = app.lookup('foo:empty').instance_eval { @actions }
        actions.should_not be_empty
        remote_run # cause to reload the buildfile
        actions = app.lookup('foo:empty').instance_eval { @actions }
        actions.should be_empty # as defined on the new buildfile
      end

      it 'should restore task prerequisites' do
        pres = app.lookup('foo:empty').send(:prerequisites).map(&:to_s)
        pres.should be_empty # no action
        app.lookup('foo:no').invoke # enhance the empty task
        pres = app.lookup('foo:empty').send(:prerequisites).map(&:to_s)
        pres.should_not be_empty
        remote_run # cause to reload the buildfile
        pres = app.lookup('foo:empty').send(:prerequisites).map(&:to_s)
        pres.should be_empty # as defined on the new buildfile
      end
    end

  end
end

