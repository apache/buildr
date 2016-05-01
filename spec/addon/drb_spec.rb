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

    def use_stdio(stdin = nil, stdout = nil, stderr = nil)
      stdin ||= StringIO.new
      stdout ||= StringIO.new
      stderr ||= StringIO.new
      cfg.update :in => stdin, :out => stdout, :err => stderr
    end

    def remote_run(*argv)
      cfg.update :argv => argv
      drb.remote_run(cfg)
    end

    def output
      cfg[:out].string
    end

    def write_buildfile(content = nil)
      write 'buildfile', content || %q{
        define('foo') do

          rule '.rbc' => '.rb' do |t|
            $stdout.puts "#{t.name} from #{t.source}"
          end

          task('hello') do
            $stdout.puts 'hi'
          end

          task('empty')

          task('no') do
            task('empty').enhance ['delete_me']
            task('empty') { $stdout.puts 'no' }
          end

          task('delete_me')

          task('create') do
            Rake::Task.define_task('created')
            rule '.rbc' => '.rb' do |t|
               $stdout.puts "#{t.name} from #{t.source}"
            end
          end

          task('exists') do
            $stdout.puts !!Buildr.application.lookup('created')
          end

          task('setopt', :name, :value) do |task, args|
            Buildr.application.options.send("#{args[:name]}=", args[:value])
          end
        end
      }
    end
  end

  include DRbHelper

  before(:each) do
    @in, @out, @err = $stdin, $stdout, $stderr
    @cfg = {
      :dir => Dir.pwd, :argv => [],
      :in => @in, :out => @out, :err => @err
    }
    @drb = Buildr::DRbApplication.clone
    @drb.send :setup
    @app = Buildr.application
  end

  after(:each) do
    $stdin, $stdout, $stderr = @in, @out, @err
  end

  describe '.run' do
    it 'starts server if no server is running' do
      expect(drb).to receive(:connect).and_raise DRb::DRbConnError
      expect(drb).to receive(:run_server!)
      expect(drb).not_to receive(:run_client)
      drb.run
    end

    it 'connects to an already started server' do
      expect(drb).to receive(:connect).and_return "client"
      expect(drb).to receive(:run_client).with "client"
      expect(drb).not_to receive(:run_server!)
      drb.run
    end
  end

  describe '.remote_run' do

    describe 'stdout' do
      it 'is redirected to client' do
        use_stdio
        expect(Buildr.application).to receive(:remote_run) do
          $stdout.puts "HELLO"
        end
        remote_run
        expect(output).to eql("HELLO\n")
      end
    end

    describe 'stderr' do
      it 'is redirected to client' do
        use_stdio
        expect(Buildr.application).to receive(:remote_run) do
          $stderr.puts "HELLO"
        end
        remote_run
        expect(cfg[:err].string).to eql("HELLO\n")
      end
    end

    describe 'stdin' do
      it 'is redirected to client' do
        use_stdio
        expect(cfg[:in]).to receive(:gets).and_return("HELLO\n")
        result = nil
        expect(Buildr.application).to receive(:remote_run) do
          result = $stdin.gets
        end
        remote_run
        expect(result).to eql("HELLO\n")
      end
    end

    describe 'server ARGV' do
      it 'is replaced with client argv' do
        expect(Buildr.application).to receive(:remote_run) do
          expect(ARGV).to eql(['hello'])
        end
        remote_run 'hello'
      end
    end

    describe 'without buildfile loaded' do
      before(:each) do
        app.instance_eval { @rakefile = nil }
        write_buildfile
      end

      it 'should load the buildfile' do
        expect(app).to receive(:top_level)
        expect { remote_run }.to run_task('foo')
      end
    end

    describe 'with unmodified buildfile' do

      before(:each) do
        write_buildfile
        app.options.rakelib = []
        app.send :load_buildfile
        drb.save_snapshot(app)
      end

      it 'should not reload the buildfile' do
        expect(app).not_to receive(:reload_buildfile)
        expect(app).to receive(:top_level)
        remote_run
      end

      it 'should not define projects again' do
        use_stdio
        expect { 2.times { remote_run 'foo:hello' } }.not_to run_task('foo')
        expect(output).to eql("hi\nhi\n")
      end

      it 'should restore task actions' do
        use_stdio
        remote_run 'foo:empty'
        expect(output).to be_empty
        2.times { remote_run 'foo:no' }
        remote_run 'foo:empty'
        actions = app.lookup('foo:empty').instance_eval { @actions }
        expect(actions).to be_empty # as originally defined
        expect(output).to be_empty
      end

      it 'should restore task prerequisites' do
        use_stdio
        remote_run 'foo:empty'
        expect(output).to be_empty
        2.times { remote_run 'foo:no' }
        remote_run 'foo:empty'
        pres = app.lookup('foo:empty').send(:prerequisites).map(&:to_s)
        expect(pres).to be_empty # as originally defined
        expect(output).to be_empty
      end

      it 'should drop runtime created tasks' do
        remote_run 'foo:create'
        expect(app.lookup('created')).not_to be_nil
        remote_run 'foo:empty'
        expect(app.lookup('created')).to be_nil
      end

      it 'should restore options' do
        remote_run 'foo:setopt[bar,baz]'
        expect(app.options.bar).to eql("baz")
        remote_run 'foo:empty'
        expect(app.options.bar).to be_nil
      end

      it 'should restore rules' do
        orig = app.instance_eval { @rules.size }
        remote_run 'foo:create'
        expect(app.instance_eval { @rules.size }).to eql(orig + 1)
        remote_run 'foo:empty'
        expect(app.instance_eval { @rules.size }).to eql(orig)
      end

    end

    describe 'with modified buildfile' do

      before(:each) do
        write_buildfile
        app.options.rakelib = []
        app.send :load_buildfile
        drb.save_snapshot(app)
        app.instance_eval { @last_loaded = Time.now - 10 }
        write_buildfile %q{
          rule '.rbc' => '.rb' do |t|
            $stdout.puts "#{t.name} from #{t.source}"
          end
          define('foo') do
            task('hello') do
              $stdout.puts 'bye'
            end
            task('empty')
            define('bar') do

            end
          end
        }
      end

      it 'should reload the buildfile' do
        expect(app).to receive(:reload_buildfile)
        expect(app).to receive(:top_level)
        remote_run
      end

      it 'should redefine projects' do
        expect { remote_run }.to run_tasks('foo', 'foo:bar')
      end

      it 'should remove tasks deleted from buildfile' do
        expect(app.lookup('foo:delete_me')).not_to be_nil
        remote_run
        expect(app.lookup('foo:delete_me')).to be_nil
      end

      it 'should redefine tasks actions' do
        actions = app.lookup('foo:empty').instance_eval { @actions }
        expect(actions).to be_empty # no action
        app.lookup('foo:no').invoke # enhance the empty task
        actions = app.lookup('foo:empty').instance_eval { @actions }
        expect(actions).not_to be_empty
        remote_run # cause to reload the buildfile
        actions = app.lookup('foo:empty').instance_eval { @actions }
        expect(actions).to be_empty # as defined on the new buildfile
      end

      it 'should redefine task prerequisites' do
        pres = app.lookup('foo:empty').send(:prerequisites).map(&:to_s)
        expect(pres).to be_empty # no action
        app.lookup('foo:no').invoke # enhance the empty task
        pres = app.lookup('foo:empty').send(:prerequisites).map(&:to_s)
        expect(pres).not_to be_empty
        remote_run # cause to reload the buildfile
        pres = app.lookup('foo:empty').send(:prerequisites).map(&:to_s)
        expect(pres).to be_empty # as defined on the new buildfile
      end

      it 'should drop runtime created tasks' do
        app.lookup('foo:create').invoke
        expect(app.lookup('created')).not_to be_nil
        remote_run 'foo:empty'
        expect(app.lookup('created')).to be_nil
      end

      it 'should restore options' do
        app.options.bar = 'baz'
        remote_run 'foo:empty'
        expect(app.options.bar).to be_nil
      end

      it 'should redefine rules' do
        orig = app.instance_eval { @rules.size }
        app.lookup('foo:create').invoke
        expect(app.instance_eval { @rules.size }).to eql(orig + 1)
        remote_run 'foo:empty'
        expect(app.instance_eval { @rules.size }).to eql(orig)
      end

    end

  end
end
