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
    expect(define('foo').cc.delay).to eq(0.2)
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

    wait_while { foo.test.compile.run_count != 1 }

    expect(foo.compile.run_count).to eq(1)
    expect(foo.test.compile.run_count).to eq(1)

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

    wait_while { foo.test.compile.run_count != 1 }

    expect(foo.compile.run_count).to eq(1)
    expect(foo.test.compile.run_count).to eq(1)
    expect(foo.resources.run_count).to eq(1)

    modify_file_times(File.join(Dir.pwd, 'src/main/java/Example.java'))

    wait_while { foo.test.compile.run_count != 2 }

    expect(foo.compile.run_count).to eq(2)
    expect(foo.test.compile.run_count).to eq(2)
    expect(foo.resources.run_count).to eq(2)

    thread.exit
  end

  # Not sure why this intermittently fails
  it 'should support subprojects', :retry => 3 do |spec|
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

    wait_while { foo.test.compile.run_count != 1 }

    expect(foo.compile.run_count).to eq(1)
    expect(foo.test.compile.run_count).to eq(1)
    expect(foo.resources.run_count).to eq(1)

    expect(file("foo/target/classes/Example.class")).to exist

    tstamp = File.mtime("foo/target/classes/Example.class")

    modify_file_times(File.join(Dir.pwd, 'foo/src/main/java/Example.java'))
    wait_while { foo.test.compile.run_count != 2 }

    expect(foo.compile.run_count).to eq(2)
    expect(foo.test.compile.run_count).to eq(2)
    expect(foo.resources.run_count).to eq(2)
    expect(File.mtime("foo/target/classes/Example.class")).not_to eq(tstamp)

    thread.exit
  end

  def modify_file_times(filename)
    # Sleep prior to touch so works with filesystems with low resolutions
    t1 = File.mtime(filename)
    while t1 == File.mtime(filename)
      sleep 1
      touch filename
    end
  end

  def wait_while(&block)
    sleep_count = 0
    while block.call && sleep_count < 15
      sleep 1
      sleep_count += 1
    end
  end

  # Not sure why this intermittently fails
  it 'should support parent and subprojects', :retry => 3 do |spec|
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

    time = Time.now

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

    wait_while { all.any? { |p| p.test.compile.run_count != 1 } }

    all.each do |p|
      expect(p.compile.run_count).to eq(1)
      expect(p.test.compile.run_count).to eq(1)
      expect(p.resources.run_count).to eq(1)
    end

    expect(file("foo/target/classes/Example.class")).to exist
    tstamp = File.mtime("foo/target/classes/Example.class")

    modify_file_times('foo/src/main/java/Example.java')
    wait_while { project("container:foo").test.compile.run_count != 2 }

    project("container:foo").tap do |p|
      expect(p.compile.run_count).to eq(2)
      expect(p.test.compile.run_count).to eq(2)
      expect(p.resources.run_count).to eq(2)
    end

    wait_while { project("container").resources.run_count != 2 }

    project("container").tap do |p|
      expect(p.compile.run_count).to eq(1) # not_needed
      expect(p.resources.run_count).to eq(2)
    end
    expect(File.mtime("foo/target/classes/Example.class")).not_to eq(tstamp)

    modify_file_times('src/main/java/Example.java')

    wait_while { project("container").resources.run_count != 3 }

    project("container").tap do |p|
      expect(p.compile.run_count).to eq(2)
      expect(p.resources.run_count).to eq(3)
    end

    thread.exit
  end
end
