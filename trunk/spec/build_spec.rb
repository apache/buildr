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


describe 'local task', :shared=>true do
  it "should execute task for project in current directory" do
    define 'foobar'
    lambda { @task.invoke }.should run_task("foobar:#{@task.name}")
  end

  it "should not execute task for projects in other directory" do
    define 'foobar', :base_dir=>'elsewhere'
    lambda { task('build').invoke }.should_not run_task('foobar:build')
  end
end


describe 'build task' do
  it_should_behave_like 'local task'
  before(:each) { @task = task('build') }
end

describe 'clean task' do
  it_should_behave_like 'local task'
  before(:each) { @task = task('clean') }
end

describe 'package task' do
  it_should_behave_like 'local task'
  before(:each) { @task = task('package') }

  it 'should execute build task as prerequisite' do
    lambda { @task.invoke }.should run_task('build')
  end
end

describe 'install task' do
  it_should_behave_like 'local task'
  before(:each) { @task = task('install') }

  it 'should execute package task as prerequisite' do
    lambda { @task.invoke }.should run_task('package')
  end
end

describe 'uninstall task' do
  it_should_behave_like 'local task'
  before(:each) { @task = task('uninstall') }
end

describe 'upload task' do
  it_should_behave_like 'local task'
  before(:each) { @task = task('upload') }

  it 'should execute package task as prerequisite' do
    lambda { @task.invoke }.should run_task('package')
  end
end


describe Project, '#build' do
  it 'should return the project\'s build task' do
    define('foo').build.should eql(task('foo:build'))
  end

  it 'should enhance the project\'s build task' do
    task 'prereq'
    task 'action'
    define 'foo' do
      build 'prereq' do
        task('action').invoke
      end
    end
    lambda { project('foo').build.invoke }.should run_tasks('prereq', 'action')
  end

  it 'should execute build task for sub-project' do
    define 'foo' do
      define 'bar'
    end
    lambda { task('foo:build').invoke }.should run_task('foo:bar:build')
  end

  it 'should not execute build task of other projects' do
    define 'foo'
    define 'bar'
    lambda { task('foo:build').invoke }.should_not run_task('bar:build')
  end
end


describe Project, '#clean' do
  it 'should return the project\'s clean task' do
    define('foo').clean.should eql(task('foo:clean'))
  end

  it 'should enhance the project\'s clean task' do
    task 'prereq'
    task 'action'
    define 'foo' do
      clean 'prereq' do
        task('action').invoke
      end
    end
    lambda { project('foo').clean.invoke }.should run_tasks('prereq', 'action')
  end

  it 'should remove target directory' do
    define 'foo' do
      self.layout[:target] = 'targeted'
    end
    mkpath 'targeted'
    lambda { project('foo').clean.invoke }.should change { File.exist?('targeted') }.from(true).to(false)
  end

  it 'should remove reports directory' do
    define 'foo' do
      self.layout[:reports] = 'reported'
    end
    mkpath 'reported'
    lambda { project('foo').clean.invoke }.should change { File.exist?('reported') }.from(true).to(false)
  end

  it 'should execute clean task for sub-project' do
    define 'foo' do
      define 'bar'
    end
    lambda { task('foo:clean').invoke }.should run_task('foo:bar:clean')
  end

  it 'should not execute clean task of other projects' do
    define 'foo'
    define 'bar'
    lambda { task('foo:clean').invoke }.should_not run_task('bar:clean')
  end
end


describe Project, '#target' do
  before :each do
    @project = define('foo', :layout=>Layout.new)
  end

  it 'should default to target' do
    @project.target.should eql('target')
  end

  it 'should set layout :target' do
    @project.target = 'bar'
    @project.layout.expand(:target).should point_to_path('bar')
  end

  it 'should come from layout :target' do
    @project.layout[:target] = 'baz'
    @project.target.should eql('baz')
  end
end


describe Project, '#reports' do
  before :each do
    @project = define('foo', :layout=>Layout.new)
  end

  it 'should default to reports' do
    @project.reports.should eql('reports')
  end

  it 'should set layout :reports' do
    @project.reports = 'bar'
    @project.layout.expand(:reports).should point_to_path('bar')
  end

  it 'should come from layout :reports' do
    @project.layout[:reports] = 'baz'
    @project.reports.should eql('baz')
  end
end
