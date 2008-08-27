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


describe Buildr::Release, '#check' do
  before do
    Buildr::Svn.stub!(:uncommitted_files).and_return('')
  end
  
  it 'should accept to release from the trunk' do
    Buildr::Svn.stub!(:repo_url).and_return('http://my.repo.org/foo/trunk')
    lambda { Release.check }.should_not raise_error
  end
  
  it 'should accept to release from a branch' do
    Buildr::Svn.stub!(:repo_url).and_return('http://my.repo.org/foo/branches/1.0')
    lambda { Release.check }.should_not raise_error
  end
  
  it 'should reject to release from a tag' do
    Buildr::Svn.stub!(:repo_url).and_return('http://my.repo.org/foo/tags/1.0.0')
    lambda { Release.check }.should raise_error(RuntimeError, "SVN URL must contain 'trunk' or 'branches/...'")
  end
  
  it 'should reject a non standard repository layout' do
    Buildr::Svn.stub!(:repo_url).and_return('http://my.repo.org/foo/bar')
    lambda { Release.check }.should raise_error(RuntimeError, "SVN URL must contain 'trunk' or 'branches/...'")
  end
  
  it 'should reject an uncommitted file' do
    Buildr::Svn.stub!(:repo_url).and_return('http://my.repo.org/foo/trunk')
    Buildr::Svn.stub!(:uncommitted_files).and_return('M      foo.rb')
    lambda { Release.check }.should raise_error(RuntimeError,
      "Uncommitted SVN files violate the First Principle Of Release!\n" +
      "M      foo.rb")
  end
end
  

describe Buildr::Release, '#extract_versions' do
  
  it 'should extract VERSION_NUMBER and NEXT_VERSION with single quotes' do
    buildfile = ["VERSION_NUMBER = '1.0.0-SNAPSHOT'", "NEXT_VERSION = '1.0.1'"].join("\n")
    Release.extract_versions(buildfile).should == ['1.0.0-SNAPSHOT', '1.0.1']
  end
  
  it 'should extract VERSION_NUMBER and NEXT_VERSION with double quotes' do
    buildfile = [%{VERSION_NUMBER = "1.0.1-SNAPSHOT"}, %{NEXT_VERSION = "1.0.2"}].join("\n")
    Release.extract_versions(buildfile).should == ['1.0.1-SNAPSHOT', '1.0.2']
  end
  
  it 'should extract VERSION_NUMBER and NEXT_VERSION without any spaces' do
    buildfile = ["VERSION_NUMBER='1.0.2-SNAPSHOT'", "NEXT_VERSION='1.0.3'"].join("\n")
    Release.extract_versions(buildfile).should == ['1.0.2-SNAPSHOT', '1.0.3']
  end
  
  it 'should extract THIS_VERSION as an alternative to VERSION_NUMBER' do
    buildfile = ["THIS_VERSION = '1.0.3-SNAPSHOT'", "NEXT_VERSION = '1.0.4'"].join("\n")
    Release.extract_versions(buildfile).should == ['1.0.3-SNAPSHOT', '1.0.4']
  end
  
  it 'should complain if no current version number' do
    buildfile = "NEXT_VERSION = '1.0.1'"
    lambda { Release.extract_versions(buildfile) }.should raise_error('Looking for THIS_VERSION = "..." in your Buildfile, none found')
  end
  
  it 'should complain if no next version number' do
    buildfile = "VERSION_NUMBER = '1.0.0-SNAPSHOT'"
    lambda { Release.extract_versions(buildfile) }.should raise_error('Looking for NEXT_VERSION = "..." in your Buildfile, none found')
  end
end


describe Buildr::Svn, '#repo_url' do
  it 'should extract the SVN URL from svn info' do
    Svn.stub!(:svn, 'info').and_return(<<EOF)
Path: .
URL: http://my.repo.org/foo/trunk
Repository Root: http://my.repo.org
Repository UUID: 12345678-9abc-def0-1234-56789abcdef0
Revision: 112
Node Kind: directory
Schedule: normal
Last Changed Author: Lacton
Last Changed Rev: 110
Last Changed Date: 2008-08-19 12:00:00 +0200 (Tue, 19 Aug 2008)
EOF
    Svn.repo_url.should == 'http://my.repo.org/foo/trunk'
  end
end


# Reference: http://svnbook.red-bean.com/en/1.4/svn.reposadmin.planning.html#svn.reposadmin.projects.chooselayout
describe Buildr::Release, '#tag url' do
  it 'should accept to tag foo/trunk' do
    Release.tag_url('http://my.repo.org/foo/trunk', '1.0.0').should == 'http://my.repo.org/foo/tags/1.0.0'
  end
  
  it 'should accept to tag foo/branches/1.0' do
    Release.tag_url('http://my.repo.org/foo/branches/1.0', '1.0.1').should == 'http://my.repo.org/foo/tags/1.0.1'
  end
  
  it 'should accept to tag trunk/foo' do
    Release.tag_url('http://my.repo.org/trunk/foo', '1.0.0').should == 'http://my.repo.org/tags/foo/1.0.0'
  end
  
  it 'should accept to tag branches/foo/1.0' do
    Release.tag_url('http://my.repo.org/branches/foo/1.0', '1.0.0').should == 'http://my.repo.org/tags/foo/1.0.0'
  end
end


describe Buildr::Release, '#with_next_version' do
  before do
    Buildr.application.stub!(:buildfile).and_return(file('buildfile'))
    write 'buildfile', <<-EOF
      THIS_VERSION = '1.1.0'
      NEXT_VERSION = '1.2.0'
      EOF
  end
  
  it 'should yield the name of an updated buildfile' do
    Release.send :with_next_version do |new_filename|
      File.read(new_filename).should == <<-EOF
      THIS_VERSION = "1.2.0"
      NEXT_VERSION = "1.2.1"
      EOF
    end
  end
  
  it 'should yield a name different from the original buildfile' do
    Release.send :with_next_version do |new_filename|
      new_filename.should_not point_to_path('buildfile')
    end
  end
  
  it 'should return the new version number' do
    new_version = Release.send(:with_next_version) {}
    new_version.should == '1.2.0'
  end
end


describe Buildr::Release, '#tag' do
  before do
    Svn.stub!(:repo_url).and_return('http://my.repo.org/foo/trunk')
    Svn.stub!(:copy)
  end
  
  it 'should tag the working copy' do
    Svn.stub!(:remove)
    Svn.should_receive(:copy).with(Dir.pwd, 'http://my.repo.org/foo/tags/1.0.1', 'Release 1.0.1')
    Release.send :tag, '1.0.1'
  end
  
  it 'should remove the tag if it already exists' do
    Svn.should_receive(:remove).with('http://my.repo.org/foo/tags/1.0.1', 'Removing old copy')
    Release.send :tag, '1.0.1'
  end
  
  it 'should accept that the tag does not exist' do
    Svn.stub!(:remove).and_raise(RuntimeError)
    Release.send :tag, '1.0.1'
  end
end


describe Buildr::Release, '#commit' do
  before do
    write 'buildfile', 'THIS_VERSION = "1.0.0"'
  end
  
  it 'should update the buildfile with the given version number' do
    Svn.stub!(:commit)
    Release.send :commit, '1.0.1-SNAPSHOT'
    file('buildfile').should contain('THIS_VERSION = "1.0.1-SNAPSHOT"')
  end
  
    it 'should commit the new buildfile on the trunk' do
      Svn.should_receive(:commit).with(File.expand_path('buildfile'), 'Changed version number to 1.0.1-SNAPSHOT')
      Release.send :commit, '1.0.1-SNAPSHOT'
    end
end