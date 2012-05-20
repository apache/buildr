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

  # monkey-patch task instance to track number of times it is run
  def instrument_task(task)
    class << task
      attr_accessor :run_count
    end
    task.run_count = 0
    task.enhance do |t|
      t.run_count += 1
    end
    task
  end

  def instrument_project(project)
    instrument_task project.compile
    instrument_task project.test.compile
    instrument_task project.resources
    project
  end

  def define_foo()
    @foo = define('foo')
    instrument_project @foo
    @foo
  end

  def foo()
    @foo
  end
end


describe Buildr::CCTask do
  include CCHelper

  it 'should default to a delay of 0.2' do
    define('foo').cc.delay.should == 0.2
  end

  it 'should compile and test:compile on initial start' do
    ['Test1.java', 'Test2.java'].map { |f| File.join('src/main/java/thepackage', f) }.
      each { |src| write src, "package thepackage; class #{src.pathmap('%n')} {}" }

    ['Test1.java', 'Test2.java'].map { |f| File.join('src/test/java/thepackage', f) }.
      each { |src| write src, "package thepackage; class #{src.pathmap('%n')} {}" }

    ['Test1.html', 'Test2.html'].map { |f| File.join('src/main/resources', f) }.
      each { |src| write src, '<html></html>' }

    define_foo()

    thread = Thread.new do
      foo.cc.invoke
    end

    sleep 1

    foo.compile.run_count.should == 1
    foo.test.compile.run_count.should == 1

    thread.exit
  end

  it 'should detect a file change' do |spec|
    write 'src/main/resources/my.properties', "# comment"
    write 'src/main/java/Example.java', "public class Example {}"
    write 'src/test/java/ExampleTest.java', "public class ExampleTest {}"

    define_foo

    thread = Thread.new do
      begin
        foo.cc.invoke
      rescue => e
        p "unexpected exception #{e.inspect}"
        p e.backtrace.join("\n")
      end
    end

    #Ick! Try to get the sleeping enough on each platform that the tests reliably pass
    sleep 1 if RUBY_VERSION >= '1.9' && !RUBY_PLATFORM[/java/]
    sleep 5 if RUBY_VERSION >= '1.8.7' && !RUBY_PLATFORM[/java/]
    sleep 1 if RUBY_PLATFORM[/java/]

    foo.compile.run_count.should == 1
    foo.test.compile.run_count.should == 1
    foo.resources.run_count.should == 1

    # Wait some time as the timestamp needs to be different on files.
    sleep 3 if Buildr::Util.win_os?
    sleep 1 unless Buildr::Util.win_os?

    touch File.join(Dir.pwd, 'src/main/java/Example.java')

    #Ick! Try to get the sleeping enough on each platform that the tests reliably pass
    sleep 1 if RUBY_VERSION >= '1.9' && !RUBY_PLATFORM[/java/]
    sleep 5 if RUBY_VERSION >= '1.8.7' && !RUBY_PLATFORM[/java/]
    sleep 1 if RUBY_PLATFORM[/java/]

    foo.compile.run_count.should == 2
    foo.test.compile.run_count.should == 2
    foo.resources.run_count.should == 2

    thread.exit
  end

  it 'should support subprojects' do |spec|
    write 'foo/src/main/java/Example.java', "public class Example {}"
    write 'foo/src/test/java/ExampleTest.java', "public class ExampleTest {}"

    define 'container' do
      define('foo')
    end

    foo = instrument_project project("container:foo")

    thread = Thread.new do
      begin
        project("container").cc.invoke
      rescue => e
        p "unexpected exception #{e.inspect}"
        p e.backtrace.join("\n").inspect
      end
    end

    sleep 1

    foo.compile.run_count.should == 1
    foo.test.compile.run_count.should == 1
    foo.resources.run_count.should == 1

    file("foo/target/classes/Example.class").should exist
    tstamp = File.mtime("foo/target/classes/Example.class")
    touch File.join(Dir.pwd, 'foo/src/main/java/Example.java')

    sleep 1

    foo.compile.run_count.should == 2
    foo.test.compile.run_count.should == 2
    foo.resources.run_count.should == 2
    File.mtime("foo/target/classes/Example.class").should_not == tstamp

    thread.exit
  end

  it 'should support parent and subprojects' do |spec|
    write 'foo/src/main/java/Example.java', "public class Example {}"
    write 'foo/src/test/java/ExampleTest.java', "public class ExampleTest {}"

    write 'bar/src/main/java/Example.java', "public class Example {}"
    write 'bar/src/test/java/ExampleTest.java', "public class ExampleTest {}"

    write 'src/main/java/Example.java', "public class Example {}"
    write 'src/test/java/ExampleTest.java', "public class ExampleTest {}"

    write 'src/main/resources/foo.txt', "content"

    define 'container' do
      define('foo')
      define('bar')
    end

    all = projects("container", "container:foo", "container:bar")
    all.each { |p| instrument_project(p) }

    thread = Thread.new do
      begin
        project("container").cc.invoke
      rescue => e
        p "unexpected exception #{e.inspect}"
        p e.backtrace.join("\n").inspect
      end
    end

    sleep 2

    all.each do |p|
      p.compile.run_count.should == 1
      p.test.compile.run_count.should == 1
      p.resources.run_count.should == 1
    end

    file("foo/target/classes/Example.class").should exist
    tstamp = File.mtime("foo/target/classes/Example.class")

    touch 'foo/src/main/java/Example.java'
    sleep 2

    project("container:foo").tap do |p|
      p.compile.run_count.should == 2
      p.test.compile.run_count.should == 2
      p.resources.run_count.should == 2
    end
    project("container").tap do |p|
      p.compile.run_count.should == 1 # not_needed
      p.test.compile.run_count.should == 1  # not_needed
      p.resources.run_count.should == 2
    end
    File.mtime("foo/target/classes/Example.class").should_not == tstamp

    touch 'src/main/java/Example.java'
    sleep 2

    project("container").tap do |p|
      p.compile.run_count.should == 2
      p.test.compile.run_count.should == 2
      p.resources.run_count.should == 3
    end

    thread.exit
  end
end
