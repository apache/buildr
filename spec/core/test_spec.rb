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


module TestHelper
  def touch_last_successful_test_run(test_task, timestamp = Time.now)
    test_task.instance_eval do
      record_successful_run
      File.utime(timestamp, timestamp, last_successful_run_file)
    end
  end
end


describe Buildr::TestTask do
  def test_task
    @test_task ||= define('foo').test
  end

  it 'should respond to :compile and return compile task' do
    expect(test_task.compile).to be_kind_of(Buildr::CompileTask)
  end

  it 'should respond to :compile and add sources to compile' do
    test_task.compile 'sources'
    expect(test_task.compile.sources).to include('sources')
  end

  it 'should respond to :compile and add action for test:compile' do
    write 'src/test/java/Test.java', 'class Test {}'
    test_task.compile { task('action').invoke }
    expect { test_task.compile.invoke }.to run_tasks('action')
  end

  it 'should execute compile tasks first' do
    write 'src/main/java/Nothing.java', 'class Nothing {}'
    write 'src/test/java/Test.java', 'class Test {}'
    define 'foo'
    expect { project('foo').test.compile.invoke }.to run_tasks(['foo:compile', 'foo:test:compile'])
  end

  it 'should respond to :resources and return resources task' do
    expect(test_task.resources).to be_kind_of(Buildr::ResourcesTask)
  end

  it 'should respond to :resources and add prerequisites to test:resources' do
    expect(file('prereq')).to receive :invoke_prerequisites
    test_task.resources 'prereq'
    test_task.compile.invoke
  end

  it 'should respond to :resources and add action for test:resources' do
    task 'action'
    test_task.resources { task('action').invoke }
    expect { test_task.resources.invoke }.to run_tasks('action')
  end

  it 'should respond to :setup and return setup task' do
    expect(test_task.setup.name).to match(/test:setup$/)
  end

  it 'should respond to :setup and add prerequisites to test:setup' do
    test_task.setup 'prereq'
    expect(test_task.setup.prerequisites).to include('prereq')
  end

  it 'should respond to :setup and add action for test:setup' do
    task 'action'
    test_task.setup { task('action').invoke }
    expect { test_task.setup.invoke }.to run_tasks('action')
  end

  it 'should respond to :teardown and return teardown task' do
    expect(test_task.teardown.name).to match(/test:teardown$/)
  end

  it 'should respond to :teardown and add prerequisites to test:teardown' do
    test_task.teardown 'prereq'
    expect(test_task.teardown.prerequisites).to include('prereq')
  end

  it 'should respond to :teardown and add action for test:teardown' do
    task 'action'
    test_task.teardown { task('action').invoke }
    expect { test_task.teardown.invoke }.to run_tasks('action')
  end

  it 'should respond to :with and return self' do
    expect(test_task.with).to be(test_task)
  end

  it 'should respond to :with and add artifacfs to compile task dependencies' do
    test_task.with 'test.jar', 'acme:example:jar:1.0'
    expect(test_task.compile.dependencies).to include(File.expand_path('test.jar'))
    expect(test_task.compile.dependencies).to include(artifact('acme:example:jar:1.0'))
  end

  it 'should respond to deprecated classpath' do
    test_task.classpath = artifact('acme:example:jar:1.0')
    expect(test_task.classpath).to be(artifact('acme:example:jar:1.0'))
  end

  it 'should respond to dependencies' do
    test_task.dependencies = artifact('acme:example:jar:1.0')
    expect(test_task.dependencies).to be(artifact('acme:example:jar:1.0'))
  end

  it 'should respond to :with and add artifacfs to task dependencies' do
    test_task.with 'test.jar', 'acme:example:jar:1.0'
    expect(test_task.dependencies).to include(File.expand_path('test.jar'))
    expect(test_task.dependencies).to include(artifact('acme:example:jar:1.0'))
  end

  it 'should response to :options and return test framework options' do
    test_task.using :foo=>'bar'
    expect(test_task.options[:foo]).to eql('bar')
  end

  it 'should respond to :using and return self' do
    expect(test_task.using).to be(test_task)
  end

  it 'should respond to :using and set value options' do
    test_task.using('foo'=>'FOO', 'bar'=>'BAR')
    expect(test_task.options[:foo]).to eql('FOO')
    expect(test_task.options[:bar]).to eql('BAR')
  end

  it 'should respond to :using with deprecated parameter style and set value options to true, up to version 1.5 since this usage was deprecated in version 1.3' do
    expect(Buildr::VERSION).to be < '1.5'
    test_task.using('foo', 'bar')
    expect(test_task.options[:foo]).to eql(true)
    expect(test_task.options[:bar]).to eql(true)
  end

  it 'should start without pre-selected test framework' do
    expect(test_task.framework).to be_nil
  end

  it 'should respond to :using and select test framework' do
    test_task.using(:testng)
    expect(test_task.framework).to eql(:testng)
  end

  it 'should infer test framework from compiled language' do
    expect { test_task.compile.using(:javac) }.to change { test_task.framework }.to(:junit)
  end

  it 'should respond to :include and return self' do
    expect(test_task.include).to be(test_task)
  end

  it 'should respond to :include and add inclusion patterns' do
    test_task.include 'Foo', 'Bar'
    expect(test_task.send(:include?, 'Foo')).to be_truthy
    expect(test_task.send(:include?, 'Bar')).to be_truthy
  end

  it 'should respond to :exclude and return self' do
    expect(test_task.exclude).to be(test_task)
  end

  it 'should respond to :exclude and add exclusion patterns' do
    test_task.exclude 'FooTest', 'BarTest'
    expect(test_task.send(:include?, 'FooTest')).to be_falsey
    expect(test_task.send(:include?, 'BarTest')).to be_falsey
    expect(test_task.send(:include?, 'BazTest')).to be_truthy
  end

  it 'should execute setup task before running tests' do
    mock = double('actions')
    test_task.setup { mock.setup }
    test_task.enhance { mock.tests }
    expect(mock).to receive(:setup).ordered
    expect(mock).to receive(:tests).ordered
    test_task.invoke
  end

  it 'should execute teardown task after running tests' do
    mock = double('actions')
    test_task.teardown { mock.teardown }
    test_task.enhance { mock.tests }
    expect(mock).to receive(:tests).ordered
    expect(mock).to receive(:teardown).ordered
    test_task.invoke
  end

  it 'should not execute teardown if setup failed' do
    test_task.setup { fail }
    expect { test_task.invoke rescue nil }.not_to run_task(test_task.teardown)
  end

  it 'should use the main compile dependencies' do
    define('foo') { compile.using(:javac).with 'group:id:jar:1.0' }
    expect(project('foo').test.dependencies).to include(artifact('group:id:jar:1.0'))
  end

  it 'should include the main compile target in its dependencies' do
    define('foo') { compile.using(:javac) }
    expect(project('foo').test.dependencies).to include(project('foo').compile.target)
  end

  it 'should include the main compile target in its dependencies, even when using non standard directories' do
    write 'src/java/Nothing.java', 'class Nothing {}'
    define('foo') { compile path_to('src/java') }
    expect(project('foo').test.dependencies).to include(project('foo').compile.target)
  end

  it 'should include the main resources target in its dependencies' do
    write 'src/main/resources/config.xml'
    expect(define('foo').test.dependencies).to include(project('foo').resources.target)
  end

  it 'should use the test compile dependencies' do
    define('foo') { test.compile.using(:javac).with 'group:id:jar:1.0' }
    expect(project('foo').test.dependencies).to include(artifact('group:id:jar:1.0'))
  end

  it 'should include the test compile target in its dependencies' do
    define('foo') { test.compile.using(:javac) }
    expect(project('foo').test.dependencies).to include(project('foo').test.compile.target)
  end

  it 'should include the test compile target in its dependencies, even when using non standard directories' do
    write 'src/test/Test.java', 'class Test {}'
    define('foo') { test.compile path_to('src/test') }
    expect(project('foo').test.dependencies).to include(project('foo').test.compile.target)
  end

  it 'should add test compile target ahead of regular compile target' do
    write 'src/main/java/Code.java'
    write 'src/test/java/Test.java'
    define 'foo'
    depends = project('foo').test.dependencies
    expect(depends.index(project('foo').test.compile.target)).to be < depends.index(project('foo').compile.target)
  end

  it 'should include the test resources target in its dependencies' do
    write 'src/test/resources/config.xml'
    expect(define('foo').test.dependencies).to include(project('foo').test.resources.target)
  end

  it 'should add test resource target ahead of regular resource target' do
    write 'src/main/resources/config.xml'
    write 'src/test/resources/config.xml'
    define 'foo'
    depends = project('foo').test.dependencies
    expect(depends.index(project('foo').test.resources.target)).to be < depends.index(project('foo').resources.target)
  end

  it 'should not have a last successful run timestamp before the tests are run' do
    expect(test_task.timestamp).to eq(Rake::EARLY)
  end

  it 'should clean after itself (test files)' do
    define('foo') { test.compile.using(:javac) }
    mkpath project('foo').test.compile.target.to_s
    expect { task('clean').invoke }.to change { File.exist?(project('foo').test.compile.target.to_s) }.to(false)
  end

  it 'should clean after itself (reports)' do
    define 'foo'
    mkpath project('foo').test.report_to.to_s
    expect { task('clean').invoke }.to change { File.exist?(project('foo').test.report_to.to_s) }.to(false)
  end

  it 'should only run tests explicitly specified if options.test is :only' do
    Buildr.options.test = :only
    write 'bar/src/main/java/Bar.java', 'public class Bar {}'
    define('bar', :version=>'1.0', :base_dir=>'bar') { package :jar }
    define('foo') { compile.with project('bar') }
    expect { task('foo:test').invoke rescue nil }.not_to run_tasks('bar:test')
  end
end


describe Buildr::TestTask, 'with no tests' do
  it 'should pass' do
    expect { define('foo').test.invoke }.not_to raise_error
  end

  it 'should report no failed tests' do
    expect { verbose(true) { define('foo').test.invoke } }.not_to show_error(/fail/i)
  end

  it 'should return no failed tests' do
    define('foo') { test.using(:junit) }
    project('foo').test.invoke
    expect(project('foo').test.failed_tests).to be_empty
  end

  it 'should return no passing tests' do
    define('foo') { test.using(:junit) }
    project('foo').test.invoke
    expect(project('foo').test.passed_tests).to be_empty
  end

  it 'should execute teardown task' do
    expect { define('foo').test.invoke }.to run_task('foo:test:teardown')
  end
end


describe Buildr::TestTask, 'with passing tests' do
  def test_task
    @test_task ||= begin
      define 'foo' do
        test.using(:junit)
        test.instance_eval do
          @framework.stub(:tests).and_return(['PassingTest1', 'PassingTest2'])
          @framework.stub(:run).and_return(['PassingTest1', 'PassingTest2'])
        end
      end
      project('foo').test
    end
  end

  it 'should pass' do
    expect { test_task.invoke }.not_to raise_error
  end

  it 'should report no failed tests' do
    expect { verbose(true) { test_task.invoke } }.not_to show_error(/fail/i)
  end

  it 'should return passed tests' do
    test_task.invoke
    expect(test_task.passed_tests).to eq(['PassingTest1', 'PassingTest2'])
  end

  it 'should return no failed tests' do
    test_task.invoke
    expect(test_task.failed_tests).to be_empty
  end

  it 'should execute teardown task' do
    expect { test_task.invoke }.to run_task('foo:test:teardown')
  end

  it 'should update the last successful run timestamp' do
    before = Time.now ; test_task.invoke ; after = Time.now
    expect(before-1..after+1).to cover(test_task.timestamp)
  end
end


describe Buildr::TestTask, 'with failed test' do
  include TestHelper

  def test_task
    @test_task ||= begin
      define 'foo' do
        test.using(:junit)
        test.instance_eval do
          @framework.stub(:tests).and_return(['FailingTest', 'PassingTest'])
          @framework.stub(:run).and_return(['PassingTest'])
        end
      end
      project('foo').test
    end
  end

  it 'should fail' do
    expect { test_task.invoke }.to raise_error(RuntimeError, /Tests failed/)
  end

  it 'should report failed tests' do
    expect { verbose(true) { test_task.invoke rescue nil } }.to show_error(/FailingTest/)
  end

  it 'should record failed tests' do
    test_task.invoke rescue nil
    expect(File.read(project('foo').path_to('target', "#{test_task.framework}-failed"))).to eq('FailingTest')
  end

  it 'should return failed tests' do
    test_task.invoke rescue nil
    expect(test_task.failed_tests).to eq(['FailingTest'])
  end

  it 'should return passing tests as well' do
    test_task.invoke rescue nil
    expect(test_task.passed_tests).to eq(['PassingTest'])
  end

  it 'should know what tests failed last time' do
    test_task.invoke rescue nil
    expect(project('foo').test.last_failures).to eq(['FailingTest'])
  end

  it 'should not fail if fail_on_failure is false' do
    test_task.using(:fail_on_failure=>false).invoke
    expect { test_task.invoke }.not_to raise_error
  end

  it 'should report failed tests even if fail_on_failure is false' do
    test_task.using(:fail_on_failure=>false)
    expect { verbose(true) { test_task.invoke } }.to show_error(/FailingTest/)
  end

  it 'should return failed tests even if fail_on_failure is false' do
    test_task.using(:fail_on_failure=>false).invoke
    expect(test_task.failed_tests).to eq(['FailingTest'])
  end

  it 'should execute teardown task' do
    expect { test_task.invoke rescue nil }.to run_task('foo:test:teardown')
  end

  it 'should not update the last successful run timestamp' do
    a_second_ago = Time.now - 1
    touch_last_successful_test_run test_task, a_second_ago
    test_task.invoke rescue nil
    expect(test_task.timestamp).to be <= a_second_ago
  end
end


describe Buildr::Project, '#test' do
  it 'should return the project\'s test task' do
    define('foo') { expect(test).to be(task('test')) }
  end

  it 'should accept prerequisites for task' do
    define('foo') { test 'prereq' }
    expect(project('foo').test.prerequisites).to include('prereq')
  end

  it 'should accept actions for task' do
    task 'action'
    define('foo') { test { task('action').invoke } }
    expect { project('foo').test.invoke }.to run_tasks('action')
  end

  it 'should set fail_on_failure true by default' do
    expect(define('foo').test.options[:fail_on_failure]).to be_truthy
  end

  it 'should set fork mode by default' do
    expect(define('foo').test.options[:fork]).to eq(:once)
  end

  it 'should set properties to empty hash by default' do
    expect(define('foo').test.options[:properties]).to eq({})
  end

  it 'should set environment variables to empty hash by default' do
    expect(define('foo').test.options[:environment]).to eq({})
  end

  it 'should inherit options from parent project' do
    define 'foo' do
      test.using :fail_on_failure=>false, :fork=>:each, :properties=>{ :foo=>'bar' }, :environment=>{ 'config'=>'config.yaml' }
      define 'bar' do
        test.using :junit
        expect(test.options[:fail_on_failure]).to be_falsey
        expect(test.options[:fork]).to eq(:each)
        expect(test.options[:properties][:foo]).to eq('bar')
        expect(test.options[:environment]['config']).to eq('config.yaml')
      end
    end
  end

  it 'should clone options from parent project when using #using' do
    define 'foo' do
      define 'bar' do
        test.using :fail_on_failure=>false, :fork=>:each, :properties=>{ :foo=>'bar' }, :environment=>{ 'config'=>'config.yaml' }
        test.using :junit
      end.invoke
      expect(test.options[:fail_on_failure]).to be_truthy
      expect(test.options[:fork]).to eq(:once)
      expect(test.options[:properties]).to eq({})
      expect(test.options[:environment]).to eq({})
    end
  end

  it 'should clone options from parent project when using #options' do
    define 'foo' do
      define 'bar' do
        test.options[:fail_on_failure] = false
        test.options[:fork] = :each
        test.options[:properties][:foo] = 'bar'
        test.options[:environment]['config'] = 'config.yaml'
        test.using :junit
      end.invoke
      expect(test.options[:fail_on_failure]).to be_truthy
      expect(test.options[:fork]).to eq(:once)
      expect(test.options[:properties]).to eq({})
      expect(test.options[:environment]).to eq({})
    end
  end

  it 'should accept to set a test property in the top project' do
    define 'foo' do
        test.options[:properties][:foo] = 'bar'
    end
    expect(project('foo').test.options[:properties][:foo]).to eq('bar')
  end

  it 'should accept to set a test property in a subproject' do
    define 'foo' do
      define 'bar' do
        test.options[:properties][:bar] = 'baz'
      end
    end
    expect(project('foo:bar').test.options[:properties][:bar]).to eq('baz')
  end

  it 'should not change options of unrelated projects when using #options' do
    define 'foo' do
      test.options[:properties][:foo] = 'bar'
    end
    define 'bar' do
      expect(test.options[:properties]).to eq({})
    end
  end

  it "should run from project's build task" do
    write 'src/main/java/Foo.java'
    write 'src/test/java/FooTest.java'
    define('foo')
    expect { task('foo:build').invoke }.to run_task('foo:test')
  end
end


describe Buildr::Project, '#test.compile' do
  it 'should identify compiler from project' do
    write 'src/test/java/com/example/Test.java'
    define('foo') do
      expect(test.compile.compiler).to eql(:javac)
    end
  end

  it 'should include identified sources' do
    write 'src/test/java/Test.java'
    define('foo') do
      expect(test.compile.sources).to include(_('src/test/java'))
    end
  end

  it 'should compile to target/test/<code>' do
    define 'foo', :target=>'targeted' do
      test.compile.using(:javac)
      expect(test.compile.target).to eql(file('targeted/test/classes'))
    end
  end

  it 'should use main compile dependencies' do
    define 'foo' do
      compile.using(:javac).with 'group:id:jar:1.0'
      test.compile.using(:javac)
    end
    expect(project('foo').test.compile.dependencies).to include(artifact('group:id:jar:1.0'))
  end

  it 'should include the main compiled target in its dependencies' do
    define 'foo' do
      compile.using(:javac).into 'bytecode'
      test.compile.using(:javac)
    end
    expect(project('foo').test.compile.dependencies).to include(file('bytecode'))
  end

  it 'should include the test framework dependencies' do
    define 'foo' do
      test.compile.using(:javac)
      test.using(:junit)
    end
    expect(project('foo').test.compile.dependencies).to include(*artifacts(JUnit.dependencies))
  end

  it 'should clean after itself' do
    write 'src/test/java/Nothing.java', 'class Nothing {}'
    define('foo') { test.compile.into 'bytecode' }
    project('foo').test.compile.invoke
    expect { project('foo').clean.invoke }.to change { File.exist?('bytecode') }.to(false)
  end
end


describe Buildr::Project, '#test.resources' do
  it 'should ignore resources unless they exist' do
    expect(define('foo').test.resources.sources).to be_empty
    expect(project('foo').test.resources.target).to be_nil
  end

  it 'should pick resources from src/test/resources if found' do
    mkpath 'src/test/resources'
    define('foo') { expect(test.resources.sources).to include(file('src/test/resources')) }
  end

  it 'should copy to the resources target directory' do
    write 'src/test/resources/config.xml', '</xml>'
    define('foo', :target=>'targeted').test.invoke
    expect(file('targeted/test/resources/config.xml')).to contain('</xml>')
  end

  it 'should create target directory even if no files to copy' do
    define('foo') do
      test.resources.filter.into('resources')
    end
    expect { file(File.expand_path('resources')).invoke }.to change { File.exist?('resources') }.to(true)
  end

  it 'should execute alongside compile task' do
    task 'action'
    define('foo') { test.resources { task('action').invoke } }
    expect { project('foo').test.compile.invoke }.to run_tasks('action')
  end
end


describe Buildr::TestTask, '#invoke' do
  include TestHelper

  def test_task
    @test_task ||= define('foo') {
      test.using(:junit)
      test.instance_eval do
        @framework.stub(:tests).and_return(['PassingTest'])
        @framework.stub(:run).and_return(['PassingTest'])
      end
    }.test
  end

  it 'should require dependencies to exist' do
    expect { test_task.with('no-such.jar').invoke }.to \
      raise_error(RuntimeError, /Don't know how to build/)
  end

  it 'should run all dependencies as prerequisites' do
    file(File.expand_path('no-such.jar')) { task('prereq').invoke }
    expect { test_task.with('no-such.jar').invoke }.to run_tasks(['prereq', 'foo:test'])
  end

  it 'should run tests if they have never run' do
    expect { test_task.invoke }.to run_task('foo:test')
  end

  it 'should not run tests if test option is off' do
    Buildr.options.test = false
    expect { test_task.invoke }.not_to run_task('foo:test')
  end

  describe 'when there was a successful test run already' do
    before do
      @a_second_ago = Time.now - 1
      src = ['main/java/Foo.java', 'main/resources/config.xml', 'test/java/FooTest.java', 'test/resources/config-test.xml'].map { |f| File.join('src', f) }
      target = ['classes/Foo.class', 'resources/config.xml', 'test/classes/FooTest.class', 'test/resources/config-test.xml'].map { |f| File.join('target', f) }
      files = ['buildfile'] + src + target
      files.each { |file| write file }
      dirs = (src + target).map { |file| file.pathmap('%d') }
      (files + dirs ).each { |path| File.utime(@a_second_ago, @a_second_ago, path) }
      touch_last_successful_test_run test_task, @a_second_ago
    end

    it 'should not run tests if nothing changed' do
      expect { test_task.invoke; sleep 1 }.not_to run_task('foo:test')
    end

    it 'should run tests if options.test is :all' do
      Buildr.options.test = :all
      expect { test_task.invoke; sleep 1 }.to run_task('foo:test')
    end

    it 'should run tests if main compile target changed' do
      touch project('foo').compile.target.to_s
      expect { test_task.invoke; sleep 1 }.to run_task('foo:test')
    end

    it 'should run tests if test compile target changed' do
      touch test_task.compile.target.to_s
      expect { test_task.invoke; sleep 1 }.to run_task('foo:test')
    end

    it 'should run tests if main resources changed' do
      touch project('foo').resources.target.to_s
      expect { test_task.invoke }.to run_task('foo:test')
    end

    it 'should run tests if test resources changed' do
      touch test_task.resources.target.to_s
      expect { test_task.invoke; sleep 1 }.to run_task('foo:test')
    end

    it 'should run tests if compile-dependent project changed' do
      write 'bar/src/main/java/Bar.java', 'public class Bar {}'
      define('bar', :version=>'1.0', :base_dir=>'bar') { package :jar }
      project('foo').compile.with project('bar')
      expect { test_task.invoke; sleep 1 }.to run_task('foo:test')
    end

    it 'should run tests if test-dependent project changed' do
      write 'bar/src/main/java/Bar.java', 'public class Bar {}'
      define('bar', :version=>'1.0', :base_dir=>'bar') { package :jar }
      test_task.with project('bar')
      expect { test_task.invoke; sleep 1 }.to run_task('foo:test')
    end

    it 'should run tests if buildfile changed' do
      touch 'buildfile'
      expect(test_task).to receive(:run_tests)
      expect { test_task.invoke; sleep 1 }.to run_task('foo:test')
    end

    it 'should not run tests if buildfile changed but IGNORE_BUILDFILE is true' do
      begin
        ENV["IGNORE_BUILDFILE"] = "true"
        expect(test_task).not_to receive(:run_tests)
        test_task.invoke
      ensure
        ENV["IGNORE_BUILDFILE"] = nil
      end
    end
  end
end

describe Rake::Task, 'test' do
  it 'should be recursive' do
    define('foo') { define 'bar' }
    expect { task('test').invoke }.to run_tasks('foo:test', 'foo:bar:test')
  end

  it 'should be local task' do
    define('foo') { define 'bar' }
    expect do
      in_original_dir project('foo:bar').base_dir do
        task('test').invoke
      end
    end.to run_task('foo:bar:test').but_not('foo:test')
  end

  it 'should stop at first failure' do
    define('myproject') do
      define('foo') { test { fail } }
      define('bar') { test { fail } }
    end
    expect { task('test').invoke rescue nil }.to run_tasks('myproject:bar:test').but_not('myproject:foo:test')
  end

  it 'should ignore failure if options.test is :all' do
    define('foo') { test { fail } }
    define('bar') { test { fail } }
    options.test = :all
    expect { task('test').invoke rescue nil }.to run_tasks('foo:test', 'bar:test')
  end

  it 'should ignore failure in subprojects if options.test is :all' do
    define('foo') {
      define('p1') { test { fail } }
      define('p2') { test {  } }
      define('p3') { test { fail } }
    }
    define('bar') { test { fail } }
    options.test = :all
    expect { task('test').invoke rescue nil }.to run_tasks('foo:p1:test', 'foo:p2:test', 'foo:p3:test', 'bar:test')
  end

  it 'should ignore failure in subprojects if environment variable test is \'all\'' do
    define('foo') {
      define('p1') { test { fail } }
      define('p2') { test {  } }
      define('p3') { test { fail } }
    }
    define('bar') { test { fail } }
    ENV['test'] = 'all'
    expect { task('test').invoke rescue nil }.to run_tasks('foo:p1:test', 'foo:p2:test', 'foo:p3:test', 'bar:test')
  end

  it 'should ignore failure if options.test is :all and target is build task ' do
    define('foo') { test { fail } }
    define('bar') { test { fail } }
    options.test = :all
    expect { task('build').invoke rescue nil }.to run_tasks('foo:test', 'bar:test')
  end

  it 'should ignore failure if environment variable test is \'all\'' do
    define('foo') { test { fail } }
    define('bar') { test { fail } }
    ENV['test'] = 'all'
    expect { task('test').invoke rescue nil }.to run_tasks('foo:test', 'bar:test')
  end

  it 'should ignore failure if environment variable TEST is \'all\'' do
    define('foo') { test { fail } }
    define('bar') { test { fail } }
    ENV['TEST'] = 'all'
    expect { task('test').invoke rescue nil }.to run_tasks('foo:test', 'bar:test')
  end

  it 'should execute no tests if options.test is false' do
    define('foo') { test { fail } }
    define('bar') { test { fail } }
    options.test = false
    expect { task('test').invoke rescue nil }.not_to run_tasks('foo:test', 'bar:test')
  end

  it 'should execute no tests if environment variable test is \'no\'' do
    define('foo') { test { fail } }
    define('bar') { test { fail } }
    ENV['test'] = 'no'
    expect { task('test').invoke rescue nil }.not_to run_tasks('foo:test', 'bar:test')
  end

  it 'should execute no tests if environment variable TEST is \'no\'' do
    define('foo') { test { fail } }
    define('bar') { test { fail } }
    ENV['TEST'] = 'no'
    expect { task('test').invoke rescue nil }.not_to run_tasks('foo:test', 'bar:test')
  end

  it "should not compile tests if environment variable test is 'no'" do
    write "src/test/java/HelloTest.java", "public class HelloTest { public void testTest() {}}"
    define('foo') { test { fail } }
    ENV['test'] = 'no'
    expect { task('test').invoke rescue nil }.not_to run_tasks('foo:test:compile')
  end
end

describe 'test rule' do
  include TestHelper

  it 'should execute test task on local project' do
    define('foo') { define 'bar' }
    expect { task('test:something').invoke }.to run_task('foo:test')
  end

  it 'should reset tasks to specific pattern' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['something', 'nothing']) }
      define 'bar' do
        test.using(:junit)
        test.instance_eval { @framework.stub(:tests).and_return(['something', 'nothing']) }
      end
    end
    task('test:something').invoke
    ['foo', 'foo:bar'].map { |name| project(name) }.each do |project|
      expect(project.test.tests).to include('something')
      expect(project.test.tests).not_to include('nothing')
    end
  end

  it 'should apply *name* pattern' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['prefix-something-suffix']) }
    end
    task('test:something').invoke
    expect(project('foo').test.tests).to include('prefix-something-suffix')
  end

  it 'should not apply *name* pattern if asterisks used' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['prefix-something', 'prefix-something-suffix']) }
    end
    task('test:*something').invoke
    expect(project('foo').test.tests).to include('prefix-something')
    expect(project('foo').test.tests).not_to include('prefix-something-suffix')
  end

  it 'should accept multiple tasks separated by commas' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['foo', 'bar', 'baz']) }
    end
    task('test:foo,bar').invoke
    expect(project('foo').test.tests).to include('foo')
    expect(project('foo').test.tests).to include('bar')
    expect(project('foo').test.tests).not_to include('baz')
  end

  it 'should execute only the named tests' do
    write 'src/test/java/TestSomething.java',
      'public class TestSomething extends junit.framework.TestCase { public void testNothing() {} }'
    write 'src/test/java/TestFails.java',
      'public class TestFails extends junit.framework.TestCase { public void testFailure() { fail(); } }'
    define 'foo'
    task('test:Something').invoke
  end

  it 'should execute the named tests even if the test task is not needed' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['something', 'nothing']) }
    end
    touch_last_successful_test_run project('foo').test
    task('test:something').invoke
    expect(project('foo').test.tests).to include('something')
  end

  it 'should not execute excluded tests' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['something', 'nothing']) }
    end
    task('test:*,-nothing').invoke
    expect(project('foo').test.tests).to include('something')
    expect(project('foo').test.tests).not_to include('nothing')
  end

  it 'should not execute tests in excluded package' do
    write 'src/test/java/com/example/foo/TestSomething.java',
      'package com.example.foo; public class TestSomething extends junit.framework.TestCase { public void testNothing() {} }'
    write 'src/test/java/com/example/bar/TestFails.java',
      'package com.example.bar; public class TestFails extends junit.framework.TestCase { public void testFailure() { fail(); } }'
    define 'foo' do
      test.using(:junit)
    end
    task('test:-com.example.bar').invoke
    expect(project('foo').test.tests).to include('com.example.foo.TestSomething')
    expect(project('foo').test.tests).not_to include('com.example.bar.TestFails')
  end

  it 'should not execute excluded tests with wildcards' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['something', 'nothing']) }
    end
    task('test:something,-s*,-n*').invoke
    expect(project('foo').test.tests).not_to include('something')
    expect(project('foo').test.tests).not_to include('nothing')
  end

  it 'should execute all tests except excluded tests' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['something', 'anything', 'nothing']) }
    end
    task('test:-nothing').invoke
    expect(project('foo').test.tests).to include('something', 'anything')
    expect(project('foo').test.tests).not_to include('nothing')
  end

  it 'should ignore exclusions in buildfile' do
    define 'foo' do
      test.using(:junit)
      test.exclude 'something'
      test.instance_eval { @framework.stub(:tests).and_return(['something', 'anything', 'nothing']) }
    end
    task('test:-nothing').invoke
    expect(project('foo').test.tests).to include('something', 'anything')
    expect(project('foo').test.tests).not_to include('nothing')
  end

  it 'should ignore inclusions in buildfile' do
    define 'foo' do
      test.using(:junit)
      test.include 'something'
      test.instance_eval { @framework.stub(:tests).and_return(['something', 'nothing']) }
    end
    task('test:nothing').invoke
    expect(project('foo').test.tests).to include('nothing')
    expect(project('foo').test.tests).not_to include('something')
  end

  it 'should not execute a test if it''s both included and excluded' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['nothing']) }
    end
    task('test:nothing,-nothing').invoke
    expect(project('foo').test.tests).not_to include('nothing')
  end

  it 'should not update the last successful test run timestamp' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval { @framework.stub(:tests).and_return(['something', 'nothing']) }
    end
    a_second_ago = Time.now - 1
    touch_last_successful_test_run project('foo').test, a_second_ago
    task('test:something').invoke
    expect(project('foo').test.timestamp).to be <= a_second_ago
  end
end

describe 'test failed' do
  include TestHelper

  def test_task
    @test_task ||= begin
      define 'foo' do
        test.using(:junit)
        test.instance_eval do
          allow(@framework).to receive(:tests).and_return(['FailingTest', 'PassingTest'])
          allow(@framework).to receive(:run).and_return(['PassingTest'])
        end
      end
      project('foo').test
    end
  end

  it 'should run the tests that failed the last time' do
    define 'foo' do
      test.using(:junit)
      test.instance_eval do
        @framework.stub(:tests).and_return(['FailingTest', 'PassingTest'])
        @framework.stub(:run).and_return(['PassingTest'])
      end
    end
    write project('foo').path_to(:target, "junit-failed"), "FailingTest"
    task('test:failed').invoke rescue nil
    expect(project('foo').test.tests).to include('FailingTest')
    expect(project('foo').test.tests).not_to include('PassingTest')
  end

  it 'should run failed tests, respecting excluded tests' do
    define 'foo' do
      test.using(:junit).exclude('ExcludedTest')
      test.instance_eval do
        @framework.stub(:tests).and_return(['FailingTest', 'PassingTest', 'ExcludedTest'])
        @framework.stub(:run).and_return(['PassingTest'])
      end
    end
    write project('foo').path_to(:target, "junit-failed"), "FailingTest\nExcludedTest"
    task('test:failed').invoke rescue nil
    expect(project('foo').test.tests).to include('FailingTest')
    expect(project('foo').test.tests).not_to include('ExcludedTest')
  end

  it 'should run only the tests that failed the last time, even when failed tests have dependencies' do
    define 'parent' do
      define 'foo' do
        test.using(:junit)
        test.instance_eval do
          @framework.stub(:tests).and_return(['PassingTest'])
          @framework.stub(:run).and_return(['PassingTest'])
        end
      end
      define 'bar' do
        test.using(:junit)
        test.enhance ["parent:foo:test"]
        test.instance_eval do
          @framework.stub(:tests).and_return(['FailingTest', 'PassingTest'])
          @framework.stub(:run).and_return(['PassingTest'])
        end
      end
    end
    write project('parent:bar').path_to(:target, "junit-failed"), "FailingTest"
    task('test:failed').invoke rescue nil
    expect(project('parent:foo').test.tests).not_to include('PassingTest')
    expect(project('parent:bar').test.tests).to include('FailingTest')
    expect(project('parent:bar').test.tests).not_to include('PassingTest')
  end

end


describe Buildr::Options, 'test' do
  it 'should be true by default' do
    expect(Buildr.options.test).to be_truthy
  end

  ['skip', 'no', 'off', 'false'].each do |value|
    it "should be false if test environment variable is '#{value}'" do
      expect { ENV['test'] = value }.to change { Buildr.options.test }.to(false)
    end
  end

  ['skip', 'no', 'off', 'false'].each do |value|
    it "should be false if TEST environment variable is '#{value}'" do
      expect { ENV['TEST'] = value }.to change { Buildr.options.test }.to(false)
    end
  end

  it 'should be :all if test environment variable is all' do
    expect { ENV['test'] = 'all' }.to change { Buildr.options.test }.to(:all)
  end

  it 'should be :all if TEST environment variable is all' do
    expect { ENV['TEST'] = 'all' }.to change { Buildr.options.test }.to(:all)
  end

  it 'should be true and warn for any other value' do
    ENV['TEST'] = 'funky'
    expect { expect(Buildr.options.test).to be(true) }.to show_warning(/expecting the environment variable/i)
  end
end


describe Buildr, 'integration' do
  it 'should return the same task from all contexts' do
    task = task('integration')
    define 'foo' do
      expect(integration).to be(task)
      define 'bar' do
        expect(integration).to be(task)
      end
    end
    expect(integration).to be(task)
  end

  it 'should respond to :setup and return setup task' do
    setup = integration.setup
    define('foo') { expect(integration.setup).to be(setup) }
  end

  it 'should respond to :setup and add prerequisites to integration:setup' do
    define('foo') { integration.setup 'prereq' }
    expect(integration.setup.prerequisites).to include('prereq')
  end

  it 'should respond to :setup and add action for integration:setup' do
    action = task('action')
    define('foo') { integration.setup { action.invoke } }
    expect { integration.setup.invoke }.to run_tasks(action)
  end

  it 'should respond to :teardown and return teardown task' do
    teardown = integration.teardown
    define('foo') { expect(integration.teardown).to be(teardown) }
  end

  it 'should respond to :teardown and add prerequisites to integration:teardown' do
    define('foo') { integration.teardown 'prereq' }
    expect(integration.teardown.prerequisites).to include('prereq')
  end

  it 'should respond to :teardown and add action for integration:teardown' do
    action = task('action')
    define('foo') { integration.teardown { action.invoke } }
    expect { integration.teardown.invoke }.to run_tasks(action)
  end
end


describe Rake::Task, 'integration' do
  it 'should be a local task' do
    define('foo') { test.using :integration }
    define('bar', :base_dir=>'other') { test.using :integration }
    expect { task('integration').invoke }.to run_task('foo:test').but_not('bar:test')
  end

  it 'should be a recursive task' do
    define 'foo' do
      test.using :integration
      define('bar') { test.using :integration }
    end
    expect { task('integration').invoke }.to run_tasks('foo:test', 'foo:bar:test')
  end

  it 'should find nested integration tests' do
    define 'foo' do
      define('bar') { test.using :integration }
    end
    expect { task('integration').invoke }.to run_tasks('foo:bar:test').but_not('foo:test')
  end

  it 'should ignore nested regular tasks' do
    define 'foo' do
      test.using :integration
      define('bar') { test.using :integration=>false }
    end
    expect { task('integration').invoke }.to run_tasks('foo:test').but_not('foo:bar:test')
  end

  it 'should agree not to run the same tasks as test' do
    define 'foo' do
      define 'bar' do
        test.using :integration
        define('baz') { test.using :integration=>false }
      end
    end
    expect { task('test').invoke }.to run_tasks('foo:test', 'foo:bar:baz:test').but_not('foo:bar:test')
    expect { task('integration').invoke }.to run_tasks('foo:bar:test').but_not('foo:test', 'foo:bar:baz:test')
  end

  it 'should run setup task before any project integration tests' do
    define('foo') { test.using :integration }
    define('bar') { test.using :integration }
    expect { task('integration').invoke }.to run_tasks([integration.setup, 'bar:test'], [integration.setup, 'foo:test'])
  end

  it 'should run teardown task after all project integrations tests' do
    define('foo') { test.using :integration }
    define('bar') { test.using :integration }
    expect { task('integration').invoke }.to run_tasks(['bar:test', integration.teardown], ['foo:test', integration.teardown])
  end

  it 'should run test cases marked for integration' do
    write 'src/test/java/FailingTest.java',
      'public class FailingTest extends junit.framework.TestCase { public void testNothing() { assertTrue(false); } }'
    define('foo') { test.using :integration }
    expect { task('test').invoke }.not_to raise_error
    expect { task('integration').invoke }.to raise_error(RuntimeError, /tests failed/i)
  end

  it 'should run setup and teardown tasks marked for integration' do
    define('foo') { test.using :integration }
    expect { task('test').invoke }.to run_tasks().but_not('foo:test:setup', 'foo:test:teardown')
    expect { task('integration').invoke }.to run_tasks('foo:test:setup', 'foo:test:teardown')
  end

  it 'should run test actions marked for integration' do
    task 'action'
    define 'foo' do
      test.using :integration, :junit
    end
    expect { task('test').invoke }.not_to change { project('foo').test.passed_tests }
    expect { task('integration').invoke }.to change { project('foo').test.passed_tests }
    expect(project('foo').test.passed_tests).to be_empty
  end

  it 'should not fail if test=all' do
    write 'src/test/java/FailingTest.java',
      'public class FailingTest extends junit.framework.TestCase { public void testNothing() { assertTrue(false); } }'
    define('foo') { test.using :integration }
    options.test = :all
    expect { task('integration').invoke }.not_to raise_error
  end

  it 'should execute by local package task' do
    define 'foo', :version=>'1.0' do
      test.using :integration
      package :jar
    end
    expect { task('package').invoke }.to run_tasks(['foo:package', 'foo:test'])
  end

  it 'should execute by local package task along with unit tests' do
    define 'foo', :version=>'1.0' do
      test.using :integration
      package :jar
      define('bar') { test.using :integration=>false }
    end
    expect { task('package').invoke }.to run_tasks(['foo:package', 'foo:test'],
      ['foo:bar:test', 'foo:bar:package'])
  end

  it 'should not execute by local package task if test=no' do
    define 'foo', :version=>'1.0' do
      test.using :integration
      package :jar
    end
    options.test = false
    expect { task('package').invoke }.to run_task('foo:package').but_not('foo:test')
  end
end


describe 'integration rule' do
  it 'should execute integration tests on local project' do
    define 'foo' do
      test.using :junit, :integration
      define 'bar'
    end
    expect { task('integration:something').invoke }.to run_task('foo:test')
  end

  it 'should reset tasks to specific pattern' do
    define 'foo' do
      test.using :junit, :integration
      test.instance_eval { @framework.stub(:tests).and_return(['something', 'nothing']) }
      define 'bar' do
        test.using :junit, :integration
        test.instance_eval { @framework.stub(:tests).and_return(['something', 'nothing']) }
      end
    end
    task('integration:something').invoke
    ['foo', 'foo:bar'].map { |name| project(name) }.each do |project|
      expect(project.test.tests).to include('something')
      expect(project.test.tests).not_to include('nothing')
    end
  end

  it 'should apply *name* pattern' do
    define 'foo' do
      test.using :junit, :integration
      test.instance_eval { @framework.stub(:tests).and_return(['prefix-something-suffix']) }
    end
    task('integration:something').invoke
    expect(project('foo').test.tests).to include('prefix-something-suffix')
  end

  it 'should not apply *name* pattern if asterisks used' do
    define 'foo' do
      test.using :junit, :integration
      test.instance_eval { @framework.stub(:tests).and_return(['prefix-something', 'prefix-something-suffix']) }
    end
    task('integration:*something').invoke
    expect(project('foo').test.tests).to include('prefix-something')
    expect(project('foo').test.tests).not_to include('prefix-something-suffix')
  end

  it 'should accept multiple tasks separated by commas' do
    define 'foo' do
      test.using :junit, :integration
      test.instance_eval { @framework.stub(:tests).and_return(['foo', 'bar', 'baz']) }
    end
    task('integration:foo,bar').invoke
    expect(project('foo').test.tests).to include('foo')
    expect(project('foo').test.tests).to include('bar')
    expect(project('foo').test.tests).not_to include('baz')
  end

  it 'should execute only the named tests' do
    write 'src/test/java/TestSomething.java',
      'public class TestSomething extends junit.framework.TestCase { public void testNothing() {} }'
    write 'src/test/java/TestFails.java',
      'public class TestFails extends junit.framework.TestCase { public void testFailure() { fail(); } }'
    define('foo') { test.using :junit, :integration }
    task('integration:Something').invoke
  end
end
