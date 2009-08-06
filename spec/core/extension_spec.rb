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


require File.join(File.dirname(__FILE__), '../spec_helpers')


describe Extension do
  
  it 'should call Extension.first_time during include' do
    TestExtension.should_receive(:first_time_called).once
    class Buildr::Project
      include TestExtension
    end
  end
  
  it 'should call before_define and after_define in order when project is defined' do
    begin
      TestExtension.initialized do |extension|
        extension.should_receive(:before_define_called).once.ordered
        extension.should_receive(:after_define_called).once.ordered
      end
      class Buildr::Project
        include TestExtension
      end
      define('foo')
    ensure
      TestExtension.initialized { |ignore| }
    end
  end

  it 'should call before_define and after_define for each project defined' do
    begin
      extensions = 0
      TestExtension.initialized do |extension|
        extensions += 1
        extension.should_receive(:before_define_called).once.ordered
        extension.should_receive(:after_define_called).once.ordered
      end
      class Buildr::Project
        include TestExtension
      end
      define('foo')
      define('bar')
      extensions.should equal(2)
    ensure  
      TestExtension.initialized { |ignore| }
    end
  end
end

module TestExtension
  include Extension
  
  def initialize(*args)
    # callback is used to obtain extension instance created by buildr
    @@initialized.call(self) if @@initialized
    super
  end
  
  def TestExtension.initialized(&block)
    @@initialized = block
  end
  
  first_time do
    TestExtension.first_time_called()
  end
  
  before_define do |project|
    project.before_define_called()
  end
  
  after_define do |project|
    project.after_define_called()
  end

  def TestExtension.first_time_called()
  end
  
end

