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

require File.join(File.dirname(__FILE__), 'spec_helpers')

unless RUBY_PLATFORM =~ /java/
  describe ENV, 'JAVA_HOME on OS X' do
    before do
      @old_home, ENV['JAVA_HOME'] = ENV['JAVA_HOME'], nil
      Config::CONFIG.should_receive(:[]).with('host_os').and_return('darwin0.9')
    end

    it 'should point to default JVM' do
      load File.expand_path('../lib/buildr/java/rjb.rb')
      ENV['JAVA_HOME'].should == '/System/Library/Frameworks/JavaVM.framework/Home'
    end

    it 'should use value of environment variable if specified' do
      ENV['JAVA_HOME'] = '/System/Library/Frameworks/JavaVM.specified'
      load File.expand_path('../lib/buildr/java/rjb.rb')
      ENV['JAVA_HOME'].should == '/System/Library/Frameworks/JavaVM.specified'
    end

    after do
      ENV['JAVA_HOME'] = @old_home
    end
  end
end