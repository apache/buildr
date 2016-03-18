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

# Return now at the resolution that the current filesystem supports
# Avoids scenario where Time.now and Time.now + 1 have same value on filesystem
def now_at_fs_resolution
  test_filename = "#{Dir.pwd}/deleteme"
  FileUtils.touch test_filename
  File.atime(test_filename)
end

module CompilerHelper
  def compile_task
    @compile_task ||= define('foo').compile.using(:javac)
  end

  def compile_task_without_compiler
    @compile_task ||= define('foo').compile
  end

  def file_task
    @file_taks ||= define('bar').file('src')
  end

  def sources
    @sources ||= ['Test1.java', 'Test2.java'].map { |f| File.join('src/main/java/thepackage', f) }.
      each { |src| write src, "package thepackage; class #{src.pathmap('%n')} {}" }
  end

  def jars
    @jars ||= begin
      write 'jars/src/main/java/Dependency.java', 'class Dependency { }'
      define 'jars', :version=>'1.0', :base_dir => 'jars' do
        package(:jar, :id=>'jar1')
        package(:jar, :id=>'jar2')
      end
      project('jars').packages.map(&:to_s)
    end
  end
end


describe Buildr::CompileTask do
  include CompilerHelper

  it 'should respond to from() and return self' do
    expect(compile_task.from(sources)).to be(compile_task)
  end

  it 'should respond to from() with FileTask having no compiler set and return self' do
    expect(compile_task_without_compiler.from(file_task)).to be(compile_task)
  end

  it 'should respond to from() and add sources' do
    compile_task.from sources, File.dirname(sources.first)
    expect(compile_task.sources).to eq(sources + [File.dirname(sources.first)])
  end

  it 'should respond to with() and return self' do
    expect(compile_task.with('test.jar')).to be(compile_task)
  end

  it 'should respond to with() and add dependencies' do
    jars = (1..3).map { |i| "test#{i}.jar" }
    compile_task.with *jars
    expect(compile_task.dependencies).to eq(artifacts(jars))
  end

  it 'should respond to into() and return self' do
    expect(compile_task.into('code')).to be(compile_task)
  end

  it 'should respond to into() and create file task' do
    compile_task.from(sources).into('code')
    expect { file('code').invoke }.to run_task('foo:compile')
  end

  it 'should respond to using() and return self' do
    expect(compile_task.using(:source=>'1.4')).to eql(compile_task)
  end

  it 'should respond to using() and set options' do
    compile_task.using(:source=>'1.4', 'target'=>'1.5')
    expect(compile_task.options.source).to eql('1.4')
    expect(compile_task.options.target).to eql('1.5')
  end

  it 'should attempt to identify compiler' do
    expect(Compiler.compilers.first).to receive(:applies_to?).at_least(:once)
    define('foo')
  end

  it 'should only support existing compilers' do
    expect { define('foo') { compile.using(:unknown) } }.to raise_error(ArgumentError, /unknown compiler/i)
  end

  it 'should allow overriding the guessed compiler' do
    write "src/main/java/com/example/Hello.java", ""
    old_compiler = nil
    new_compiler = nil
    define('foo') {
      old_compiler = compile.compiler
      compile.using(:scalac)
      new_compiler = compile.compiler
    }
    expect(old_compiler).to eq(:javac)
    expect(new_compiler).to eq(:scalac)
  end
end


describe Buildr::CompileTask, '#compiler' do
  it 'should be nil if no compiler identifier' do
    expect(define('foo').compile.compiler).to be_nil
  end

  it 'should return the selected compiler' do
    define('foo') { compile.using(:javac) }
    expect(project('foo').compile.compiler).to eql(:javac)
  end

  it 'should attempt to identify compiler if sources are specified' do
    define 'foo' do
      Compiler.compilers.first.should_receive(:applies_to?).at_least(:once)
      compile.from('sources').compiler
    end
  end

  it 'should allow supressing compilation' do
    write 'src/main/java/package/Test.java', 'class Test {}'
    define 'foo' do
      compile.sources.clear
    end
    project('foo').compile.invoke
    expect(Dir['target/classes/*']).to be_empty
  end
end


describe Buildr::CompileTask, '#language' do
  it 'should be nil if no compiler identifier' do
    expect(define('foo').compile.language).to be_nil
  end

  it 'should return the appropriate language' do
    define('foo') { compile.using(:javac) }
    expect(project('foo').compile.language).to eql(:java)
  end
end


describe Buildr::CompileTask, '#sources' do
  include CompilerHelper

  it 'should be empty if no sources in default directory' do
    expect(compile_task.sources).to be_empty
  end

  it 'should point to default directory if it contains sources' do
    write 'src/main/java', ''
    expect(compile_task.sources.first).to point_to_path('src/main/java')
  end

  it 'should be an array' do
    compile_task.sources += sources
    expect(compile_task.sources).to eq(sources)
  end

  it 'should allow files' do
    compile_task.from(sources).into('classes').invoke
    sources.each { |src| expect(file(src.pathmap('classes/thepackage/%n.class'))).to exist }
  end

  it 'should allow directories' do
    compile_task.from(File.dirname(sources.first)).into('classes').invoke
    sources.each { |src| expect(file(src.pathmap('classes/thepackage/%n.class'))).to exist }
  end

  it 'should allow tasks' do
    expect { compile_task.from(file(sources.first)).into('classes').invoke }.to run_task('foo:compile')
  end

  it 'should act as prerequisites' do
    file('src2') { |task| task('prereq').invoke ; mkpath task.name }
    expect { compile_task.from('src2').into('classes').invoke }.to run_task('prereq')
  end
end


describe Buildr::CompileTask, '#dependencies' do
  include CompilerHelper

  it 'should be empty' do
    expect(compile_task.dependencies).to be_empty
  end

  it 'should be an array' do
    compile_task.dependencies += jars
    expect(compile_task.dependencies).to eq(jars)
  end

  it 'should allow files' do
    compile_task.from(sources).with(jars).into('classes').invoke
    sources.each { |src| expect(file(src.pathmap('classes/thepackage/%n.class'))).to exist }
  end

  it 'should allow tasks' do
    compile_task.from(sources).with(file(jars.first)).into('classes').invoke
  end

  it 'should allow artifacts' do
    artifact('group:id:jar:1.0') { |task| mkpath File.dirname(task.to_s) ; cp jars.first.to_s, task.to_s }.enhance jars
    compile_task.from(sources).with('group:id:jar:1.0').into('classes').invoke
  end

  it 'should allow projects' do
    define('bar', :version=>'1', :group=>'self') { package :jar }
    compile_task.with project('bar')
    expect(compile_task.dependencies).to eq(project('bar').packages)
  end

  it 'should be accessible as classpath up to version 1.5 since it was deprecated in version 1.3' do
    expect(Buildr::VERSION).to be < '1.5'
    expect { compile_task.classpath = jars }.to change(compile_task, :dependencies).to(jars)
    expect { compile_task.dependencies = [] }.to change(compile_task, :classpath).to([])
  end

end


describe Buildr::CompileTask, '#target' do
  include CompilerHelper

  it 'should be a file task' do
    compile_task.from(@sources).into('classes')
    expect(compile_task.target).to be_kind_of(Rake::FileTask)
  end

  it 'should accept a task' do
    task = file('classes')
    expect(compile_task.into(task).target).to be(task)
  end

  it 'should create dependency in file task when set' do
    compile_task.from(sources).into('classes')
    expect { file('classes').invoke }.to run_task('foo:compile')
  end
end


describe Buildr::CompileTask, '#options' do
  include CompilerHelper

  it 'should have getter and setter methods' do
    compile_task.options.foo = 'bar'
    expect(compile_task.options.foo).to eql('bar')
  end

  it 'should have bracket accessors' do
    compile_task.options[:foo] = 'bar'
    expect(compile_task.options[:foo]).to eql('bar')
  end

  it 'should map from bracket accessor to get/set accessor' do
    compile_task.options[:foo] = 'bar'
    expect(compile_task.options.foo).to eql('bar')
  end

  it 'should be independent of parent' do
    define 'foo' do
      compile.using(:javac, :source=>'1.4')
      define 'bar' do
        compile.using(:javac, :source=>'1.5')
      end
    end
    expect(project('foo').compile.options.source).to eql('1.4')
    expect(project('foo:bar').compile.options.source).to eql('1.5')
  end
end


describe Buildr::CompileTask, '#invoke' do
  include CompilerHelper

  it 'should compile into target directory' do
    compile_task.from(sources).into('code').invoke
    expect(Dir['code/thepackage/*.class']).not_to be_empty
  end

  it 'should compile only once' do
    compile_task.from(sources)
    expect { compile_task.target.invoke }.to run_task('foo:compile')
    expect { compile_task.invoke }.not_to run_task('foo:compile')
  end

  it 'should compile if there are source files to compile' do
    expect { compile_task.from(sources).invoke }.to run_task('foo:compile')
  end

  it 'should not compile unless there are source files to compile' do
    expect { compile_task.invoke }.not_to run_task('foo:compile')
  end

  it 'should require source file or directory to exist' do
    expect { compile_task.from('empty').into('classes').invoke }.to raise_error(RuntimeError, /Don't know how to build/)
  end

  it 'should run all source files as prerequisites' do
    mkpath 'src'
    expect(file('src')).to receive :invoke_prerequisites
    compile_task.from('src').invoke
  end

  it 'should require dependencies to exist' do
    expect { compile_task.from(sources).with('no-such.jar').into('classes').invoke }.to \
      raise_error(RuntimeError, /Don't know how to build/)
  end

  it 'should run all dependencies as prerequisites' do
    file(File.expand_path('no-such.jar')) { |task| task('prereq').invoke }
    expect { compile_task.from(sources).with('no-such.jar').into('classes').invoke }.to run_tasks(['prereq', 'foo:compile'])
  end

  it 'should force compilation if no target' do
    expect { compile_task.from(sources).invoke }.to run_task('foo:compile')
  end

  it 'should force compilation if target empty' do
    time = now_at_fs_resolution
    mkpath compile_task.target.to_s
    File.utime(time - 1, time - 1, compile_task.target.to_s)
    expect { compile_task.from(sources).invoke }.to run_task('foo:compile')
  end

  it 'should force compilation if sources newer than compiled' do
    # Simulate class files that are older than source files.
    time = now_at_fs_resolution
    sources.each { |src| File.utime(time + 1, time + 1, src) }
    sources.map { |src| src.pathmap("#{compile_task.target}/thepackage/%n.class") }.
      each { |kls| write kls ; File.utime(time, time, kls) }
    File.utime(time - 1, time - 1, project('foo').compile.target.to_s)
    expect { compile_task.from(sources).invoke }.to run_task('foo:compile')
  end

  it 'should not force compilation if sources older than compiled' do
    # When everything has the same timestamp, nothing is compiled again.
    time = now_at_fs_resolution
    sources.map { |src| File.utime(time, time, src); src.pathmap("#{compile_task.target}/thepackage/%n.class") }.
      each { |kls| write kls ; File.utime(time, time, kls) }
    expect { compile_task.from(sources).invoke }.not_to run_task('foo:compile')
  end

  it 'should not force compilation if dependencies older than compiled' do
    jars; project('jars').task("package").invoke
    time = now_at_fs_resolution
    jars.each { |jar| File.utime(time - 1 , time - 1, jar) }
    sources.map { |src| File.utime(time, time, src); src.pathmap("#{compile_task.target}/thepackage/%n.class") }.
      each { |kls| write kls ; File.utime(time, time, kls) }
    expect { compile_task.from(sources).with(jars).invoke }.not_to run_task('foo:compile')
  end

  it 'should force compilation if dependencies newer than compiled' do
    jars; project('jars').task("package").invoke
    # On my machine the times end up the same, so need to push dependencies in the past.
    time = now_at_fs_resolution
    sources.map { |src| src.pathmap("#{compile_task.target}/thepackage/%n.class") }.
      each { |kls| write kls ; File.utime(time - 1, time - 1, kls) }
    File.utime(time - 1, time - 1, project('foo').compile.target.to_s)
    jars.each { |jar| File.utime(time + 1, time + 1, jar) }
    expect { compile_task.from(sources).with(jars).invoke }.to run_task('foo:compile')
  end

  it 'should timestamp target directory if specified' do
    time = now_at_fs_resolution - 10
    mkpath compile_task.target.to_s
    File.utime(time, time, compile_task.target.to_s)
    expect(compile_task.timestamp).to be_within(1).of(time)
  end

  it 'should touch target if anything compiled' do
    mkpath compile_task.target.to_s
    File.utime(now_at_fs_resolution - 10, now_at_fs_resolution - 10, compile_task.target.to_s)
    compile_task.from(sources).invoke
    expect(File.stat(compile_task.target.to_s).mtime).to be_within(2).of(now_at_fs_resolution)
  end

  it 'should not touch target if nothing compiled' do
    mkpath compile_task.target.to_s
    File.utime(now_at_fs_resolution - 10, now_at_fs_resolution - 10, compile_task.target.to_s)
    compile_task.invoke
    expect(File.stat(compile_task.target.to_s).mtime).to be_within(2).of(now_at_fs_resolution - 10)
  end

  it 'should not touch target if failed to compile' do
    mkpath compile_task.target.to_s
    File.utime(now_at_fs_resolution - 10, now_at_fs_resolution - 10, compile_task.target.to_s)
    write 'failed.java', 'not a class'
    suppress_stdout { compile_task.from('failed.java').invoke rescue nil }
    expect(File.stat(compile_task.target.to_s).mtime).to be_within(2).of(now_at_fs_resolution - 10)
  end

  it 'should complain if source directories and no compiler selected' do
    mkpath 'sources'
    define 'bar' do
      expect { compile.from('sources').invoke }.to raise_error(RuntimeError, /no compiler selected/i)
    end
  end

  it 'should not unnecessarily recompile files explicitly added to compile list (BUILDR-611)' do
    mkpath 'src/other'
    write 'src/other/Foo.java', 'package foo; public class Foo {}'
    compile_task.from FileList['src/other/**.java']
    mkpath 'target/classes/foo'
    touch 'target/classes/foo/Foo.class'
    File.utime(now_at_fs_resolution - 10, now_at_fs_resolution - 10, compile_task.target.to_s)
    compile_task.invoke
    expect(File.stat(compile_task.target.to_s).mtime).to be_within(2).of(now_at_fs_resolution - 10)
  end
end


shared_examples_for 'accessor task' do
  it 'should return a task' do
    expect(define('foo').send(@task_name)).to be_kind_of(Rake::Task)
  end

  it 'should always return the same task' do
    task_name, task = @task_name, nil
    define('foo') { task = self.send(task_name) }
    expect(project('foo').send(task_name)).to be(task)
  end

  it 'should be unique for the project' do
    define('foo') { define 'bar' }
    expect(project('foo').send(@task_name)).not_to eql(project('foo:bar').send(@task_name))
  end

  it 'should be named after the project' do
    define('foo') { define 'bar' }
    expect(project('foo:bar').send(@task_name).name).to eql("foo:bar:#{@task_name}")
  end
end


describe Project, '#compile' do
  before { @task_name = 'compile' }
  it_should_behave_like 'accessor task'

  it 'should return a compile task' do
    expect(define('foo').compile).to be_instance_of(CompileTask)
  end

  it 'should accept sources and add to source list' do
    define('foo') { compile('file1', 'file2') }
    expect(project('foo').compile.sources).to include('file1', 'file2')
  end

  it 'should accept block and enhance task' do
    write 'src/main/java/Test.java', 'class Test {}'
    action = task('action')
    define('foo') { compile { action.invoke } }
    expect { project('foo').compile.invoke }.to run_tasks('foo:compile', action)
  end

  it 'should execute resources task' do
    define 'foo'
    expect { project('foo').compile.invoke }.to run_task('foo:resources')
  end

  it 'should be recursive' do
    write 'bar/src/main/java/Test.java', 'class Test {}'
    define('foo') { define 'bar' }
    expect { project('foo').compile.invoke }.to run_task('foo:bar:compile')
  end

  it 'should be a local task' do
    write 'bar/src/main/java/Test.java', 'class Test {}'
    define('foo') { define 'bar' }
    expect do
      in_original_dir project('foo:bar').base_dir do
        task('compile').invoke
      end
    end.to run_task('foo:bar:compile').but_not('foo:compile')
  end

  it 'should run from build task' do
    write 'bar/src/main/java/Test.java', 'class Test {}'
    define('foo') { define 'bar' }
    expect { task('build').invoke }.to run_task('foo:bar:compile')
  end

  it 'should clean after itself' do
    mkpath 'code'
    define('foo') { compile.into('code') }
    expect { task('clean').invoke }.to change { File.exist?('code') }.to(false)
  end
end


describe Project, '#resources' do
  before { @task_name = 'resources' }
  it_should_behave_like 'accessor task'

  it 'should return a resources task' do
    expect(define('foo').resources).to be_instance_of(ResourcesTask)
  end

  it 'should provide a filter' do
    expect(define('foo').resources.filter).to be_instance_of(Filter)
  end

  it 'should include src/main/resources as source directory' do
    write 'src/main/resources/test'
    expect(define('foo').resources.sources.first).to point_to_path('src/main/resources')
  end

  it 'should include src/main/resources directory only if it exists' do
    expect(define('foo').resources.sources).to be_empty
  end

  it 'should accept prerequisites' do
    tasks = ['task1', 'task2'].each { |name| task(name) }
    define('foo') { resources 'task1', 'task2' }
    expect { project('foo').resources.invoke }.to run_tasks('task1', 'task2')
  end

  it 'should respond to from and add additional sources' do
    write 'src/main/resources/original'
    write 'extra/spicy'
    define('foo') { resources.from 'extra' }
    project('foo').resources.invoke
    expect(FileList['target/resources/*'].sort).to  eq(['target/resources/original', 'target/resources/spicy'])
  end

  it 'should pass include pattern to filter' do
    3.times { |i| write "src/main/resources/test#{i + 1}" }
    define('foo') { resources.include('test2') }
    project('foo').resources.invoke
    expect(FileList['target/resources/*']).to  eq(['target/resources/test2'])
  end

  it 'should pass exclude pattern to filter' do
    3.times { |i| write "src/main/resources/test#{i + 1}" }
    define('foo') { resources.exclude('test2') }
    project('foo').resources.invoke
    expect(FileList['target/resources/*'].sort).to  eq(['target/resources/test1', 'target/resources/test3'])
  end

  it 'should accept block and enhance task' do
    action = task('action')
    define('foo') { resources { action.invoke } }
    expect { project('foo').resources.invoke }.to run_tasks('foo:resources', action)
  end

  it 'should set target directory to target/resources' do
    write 'src/main/resources/foo'
    expect(define('foo').resources.target.to_s).to point_to_path('target/resources')
  end

  it 'should use provided target directoy' do
    define('foo') { resources.filter.into('the_resources') }
    expect(project('foo').resources.target.to_s).to point_to_path('the_resources')
  end

  it 'should create file task for target directory' do
    write 'src/main/resources/foo'
    define 'foo'
    project('foo').file('target/resources').invoke
    expect(file('target/resources/foo')).to exist
  end

  it 'should copy resources to target directory' do
    write 'src/main/resources/foo', 'Foo'
    define('foo').compile.invoke
    expect(file('target/resources/foo')).to contain('Foo')
  end

  it 'should copy new resources to target directory' do
    time = now_at_fs_resolution
    mkdir_p 'target/resources'
    File.utime(time-10, time-10, 'target/resources')

    write 'src/main/resources/foo', 'Foo'

    define('foo')
    project('foo').file('target/resources').invoke
    expect(file('target/resources/foo')).to exist
  end

  it 'should copy updated resources to target directory' do
    time = now_at_fs_resolution
    mkdir_p 'target/resources'
    write 'target/resources/foo', 'Foo'
    File.utime(time-10, time-10, 'target/resources')
    File.utime(time-10, time-10, 'target/resources/foo')

    write 'src/main/resources/foo', 'Foo2'
    define('foo')
    project('foo').file('target/resources').invoke
    expect(file('target/resources/foo')).to contain('Foo2')
  end

  it 'should not create target directory unless there are resources' do
    define('foo').compile.invoke
    expect(file('target/resources')).not_to exist
  end

  it 'should run from target/resources' do
    write 'src/main/resources/test'
    define('foo')
    expect { project('foo').resources.target.invoke }.to change { File.exist?('target/resources/test') }.to(true)
  end

  it 'should not be recursive' do
    define('foo') { define 'bar' }
    expect { project('foo').resources.invoke }.not_to run_task('foo:bar:resources')
  end

  it 'should use current profile for filtering' do
    write 'profiles.yaml', <<-YAML
      development:
        filter:
          foo: bar
      test:
        filter:
          foo: baz
    YAML
    write 'src/main/resources/foo', '${foo}'
    define('foo').compile.invoke
    expect(file('target/resources/foo')).to contain('bar')
  end

  it 'should use current profile as default for filtering' do
    write 'profiles.yaml', <<-YAML
      development:
        filter:
          foo: bar
    YAML
    write 'src/main/resources/foo', '${foo} ${baz}'
    define('foo') do
      resources.filter.using 'baz' => 'qux'
    end
    project('foo').compile.invoke
    expect(file('target/resources/foo')).to contain('bar qux')
  end

  it 'should allow clearing default filter mapping' do
    write 'profiles.yaml', <<-YAML
      development:
        filter:
          foo: bar
    YAML
    write 'src/main/resources/foo', '${foo} ${baz}'
    define('foo') do
      resources.filter.mapping.clear
      resources.filter.using 'baz' => 'qux'
    end
    project('foo').compile.invoke
    expect(file('target/resources/foo')).to contain('${foo} qux')
  end
end
