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
  
  before(:each) do
    @drb = Buildr::DRbApplication
  end
  
  describe '.run' do
    it 'starts server if no server is running' do
      @drb.should_receive(:connect).and_raise DRb::DRbConnError
      @drb.should_receive(:run_server!)
      @drb.should_not_receive(:run_client)
      @drb.run
    end

    it 'connects to an already started server' do
      @drb.should_receive(:connect).and_return "client"
      @drb.should_receive(:run_client).with "client"
      @drb.should_not_receive(:run_server!)
      @drb.run
    end
  end

  describe '.remote_run' do
    
    before(:each) do 
      @cfg = { 
        :dir => Dir.pwd, :argv => [],
        :in => StringIO.new, :out => StringIO.new, :err => StringIO.new
      }
    end

    describe 'stdout' do
      it 'is redirected to client' do 
        Buildr.application.should_receive(:remote_run) do 
          $stdout.puts "HELLO"
        end
        @drb.remote_run(@cfg)
        @cfg[:out].string.should eql("HELLO\n")
      end
    end

    describe 'stderr' do 
      it 'is redirected to client' do
        Buildr.application.should_receive(:remote_run) do 
          $stderr.puts "HELLO"
        end
        @drb.remote_run(@cfg)
        @cfg[:err].string.should eql("HELLO\n")
      end
    end

    describe 'stdin' do
      it 'is redirected to client' do
        @cfg[:in].should_receive(:gets).and_return("HELLO\n")
        Buildr.application.should_receive(:remote_run) do 
          $stdin.gets.should eql("HELLO\n")
        end
        @drb.remote_run(@cfg)
      end
    end

  end
end

