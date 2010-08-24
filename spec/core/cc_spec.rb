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


require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helpers'))

module CCHelper
  def setup_cc
    project = define('foo')

    cc = project.cc
    project.stub!(:task).with(:cc).and_return(cc)

    compile = mock 'compile'
    project.stub!(:task).with(:compile).and_return(compile)

    test_compile = mock 'test:compile'
    project.stub!(:task).with('test:compile').and_return(test_compile)

    filter = mock('resources').tap do |resources|
      project.stub!(:task).with(:resources).and_return(resources)

      back = mock 'filter'
      resources.stub!(:filter).and_return(back)

      back
    end

    sources
    tests
    resources

    [ project, compile, test_compile, filter ]
  end

  def sources
    @sources ||= ['Test1.java', 'Test2.java'].map { |f| File.join('src/main/java/thepackage', f) }.
      each { |src| write src, "package thepackage; class #{src.pathmap('%n')} {}" }
  end

  def tests
    @tests ||= ['Test1.java', 'Test2.java'].map { |f| File.join('src/test/java/thepackage', f) }.
      each { |src| write src, "package thepackage; class #{src.pathmap('%n')} {}" }
  end

  def resources
    @resources ||= ['Test1.html', 'Test2.html'].map { |f| File.join('src/main/resources', f) }.
      each { |src| write src, '<html></html>' }
  end
end

describe Buildr::CCTask do
  include CCHelper

  it 'should default to a delay of 0.2' do
    define('foo').cc.delay.should == 0.2
  end

  it 'should compile and test:compile on initial start' do
    project, compile, test_compile, filter = setup_cc

    compile.should_receive :invoke
    test_compile.should_receive :invoke
    filter.should_not_receive :run

    thread = Thread.new do
      project.cc.invoke
    end

    sleep 0.5

    thread.exit
  end

  it 'should detect a file change' do |spec|
    
    write 'src/main/java/Example.java', "public class Example {}"
    write 'src/test/java/ExampleTest.java', "public class ExampleTest {}"
    
    project = define("foo")
    cc = project.cc
    
    compile = project.compile
    

    test_compile = project.test.compile

    filter = project.resources
    
    # After first period:
    compile.should_receive :invoke
    test_compile.should_receive :invoke
    filter.should_not_receive :run
    
    thread = Thread.new do
      project.cc.invoke
    end
    
    sleep 0.5
    
    compile.should_receive :reenable
    compile.should_receive :invoke

    test_compile.should_receive :reenable
    test_compile.should_receive :invoke

    filter.should_not_receive :run
    
    sleep 1 # Wait one sec as the timestamp needs to be different.
    touch File.join(Dir.pwd, 'src/main/java/Example.java')
    sleep 0.3# Wait one standard delay and half
    
    thread.exit
  end
  
  
  it 'should support subprojects' do |spec|
    
    write 'foo/src/main/java/Example.java', "public class Example {}"
    write 'foo/src/test/java/ExampleTest.java', "public class ExampleTest {}"
    
    define 'container' do
      define('foo')
    end
    
    project = project("container:foo")
    cc = project.cc
    
    compile = project.compile

    test_compile = project.test.compile

    filter = project.resources
    
    
    # After first period:
    compile.should_receive :invoke
    test_compile.should_receive :invoke
    filter.should_not_receive :run
    
    thread = Thread.new do
      project("container").cc.invoke
    end
    
    sleep 0.5
    
    # After we changed the file:
    compile.should_receive :reenable
    compile.should_receive :invoke

    test_compile.should_receive :reenable
    test_compile.should_receive :invoke
    
    filter.should_not_receive :run
    
    sleep 1 # Wait one sec as the timestamp needs to be different.
    touch File.join(Dir.pwd, 'foo/src/main/java/Example.java')
    sleep 0.3 # Wait one standard delay and half
    
    thread.exit
  end
end
