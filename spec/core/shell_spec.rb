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

describe Project, '.shell' do

  it 'should return the project\'s shell task' do
    define('foo')
    expect(project('foo').shell.name).to eql('foo:shell')
  end

  it 'should return a ShellTask' do
    define('foo')
    expect(project('foo').shell).to be_kind_of(Shell::ShellTask)
  end

  it 'should include compile and test.compile dependencies' do
    define('foo') do
      compile.using(:javac).with 'group:compile:jar:1.0'
      test.compile.using(:javac).with 'group:test:jar:1.0'
    end
    expect(project('foo').shell.classpath).to include(artifact('group:compile:jar:1.0'))
    expect(project('foo').shell.classpath).to include(artifact('group:test:jar:1.0'))
  end

  it 'should respond to using() and return self' do
    define 'foo' do
      expect(shell.using(:foo=>'Fooing')).to be(shell)
    end
  end

  it 'should respond to using() and accept options' do
    define 'foo' do
      shell.using :foo=>'Fooing'
    end
    expect(project('foo').shell.options[:foo]).to eql('Fooing')
  end

  it 'should select provider using shell.using' do
    define 'foo' do
      shell.using :bsh
    end
    expect(project('foo').shell.provider).to be_a(Shell::BeanShell)
  end

  it 'should select runner based on compile language' do
    write 'src/main/java/Test.java', 'class Test {}'
    define 'foo' do
      # compile language detected as :java
    end
    expect(project('foo').shell.provider).to be_a(Shell::BeanShell)
  end

  it 'should depend on project''s compile task' do
    define 'foo'
    expect(project('foo').shell.prerequisites).to include(project('foo').compile)
  end

  it 'should be local task' do
    define 'foo' do
      define('bar') do
        shell.using :bsh
      end
    end
    task = project('foo:bar').shell
    expect(task).to receive(:invoke_prerequisites)
    expect(task).to receive(:run)
    in_original_dir(project('foo:bar').base_dir) { task('shell').invoke }
  end

  it 'should not recurse' do
    define 'foo' do
      shell.using :bsh
      define('bar') { shell.using :bsh }
    end
    expect(project('foo:bar').shell).not_to receive(:invoke_prerequisites)
    expect(project('foo:bar').shell).not_to receive(:run)
    expect(project('foo').shell).to receive(:run)
    project('foo').shell.invoke
  end

  it 'should call shell provider with task configuration' do
    define 'foo' do
      shell.using :bsh
    end
    shell = project('foo').shell
    expect(shell.provider).to receive(:launch).with(shell)
    project('foo').shell.invoke
  end
end

shared_examples_for "shell provider" do

  it 'should have launch method accepting shell task' do
    expect(@instance.method(:launch)).not_to be_nil
    expect(@instance.method(:launch).arity).to be === 1
  end

end

Shell.providers.each do |provider|
  describe provider do
    before do
      @provider = provider
      @project = define('foo') {}
      @instance = provider.new(@project)
      @project.shell.using @provider.to_sym
    end

    it_should_behave_like "shell provider"

    it 'should call Java::Commands.java with :java_args' do
      @project.shell.using :java_args => ["-Xx"]
      expect(Java::Commands).to receive(:java) do |*args|
        expect(args.last).to be_a(Hash)
        expect(args.last.keys).to include(:java_args)
        expect(args.last[:java_args]).to include('-Xx')
        
      end
      project('foo').shell.invoke
    end

    it 'should call Java::Commands.java with :properties' do
      @project.shell.using :properties => {:foo => "bar"}
      expect(Java::Commands).to receive(:java) do |*args|
        expect(args.last).to be_a(Hash)
        expect(args.last.keys).to include(:properties)
        expect(args.last[:properties][:foo]).to eq("bar")
        
      end
      project('foo').shell.invoke
    end
  end
end
