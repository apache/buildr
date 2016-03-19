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

shared_examples_for 'local task' do
  it "should execute task for project in current directory" do
    define 'foobar'
    expect { @task.invoke }.to run_task("foobar:#{@task.name}")
  end

  it "should not execute task for projects in other directory" do
    define 'foobar', :base_dir=>'elsewhere'
    expect { task('build').invoke }.not_to run_task('foobar:build')
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
    expect { @task.invoke }.to run_task('build')
  end
end

describe 'install task' do
  it_should_behave_like 'local task'
  before(:each) { @task = task('install') }

  it 'should execute package task as prerequisite' do
    expect { @task.invoke }.to run_task('package')
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
    expect { @task.invoke }.to run_task('package')
  end
end


describe Project, '#build' do
  it 'should return the project\'s build task' do
    expect(define('foo').build).to eql(task('foo:build'))
  end

  it 'should enhance the project\'s build task' do
    task 'prereq'
    task 'action'
    define 'foo' do
      build 'prereq' do
        task('action').invoke
      end
    end
    expect { project('foo').build.invoke }.to run_tasks('prereq', 'action')
  end

  it 'should execute build task for sub-project' do
    define 'foo' do
      define 'bar'
    end
    expect { task('foo:build').invoke }.to run_task('foo:bar:build')
  end

  it 'should not execute build task of other projects' do
    define 'foo'
    define 'bar'
    expect { task('foo:build').invoke }.not_to run_task('bar:build')
  end
end


describe Project, '#clean' do
  it 'should return the project\'s clean task' do
    expect(define('foo').clean).to eql(task('foo:clean'))
  end

  it 'should enhance the project\'s clean task' do
    task 'prereq'
    task 'action'
    define 'foo' do
      clean 'prereq' do
        task('action').invoke
      end
    end
    expect { project('foo').clean.invoke }.to run_tasks('prereq', 'action')
  end

  it 'should remove target directory' do
    define 'foo' do
      self.layout[:target] = 'targeted'
    end
    mkpath 'targeted'
    expect { project('foo').clean.invoke }.to change { File.exist?('targeted') }.from(true).to(false)
  end

  it 'should remove reports directory' do
    define 'foo' do
      self.layout[:reports] = 'reported'
    end
    mkpath 'reported'
    expect { project('foo').clean.invoke }.to change { File.exist?('reported') }.from(true).to(false)
  end

  it 'should execute clean task for sub-project' do
    define 'foo' do
      define 'bar'
    end
    expect { task('foo:clean').invoke }.to run_task('foo:bar:clean')
  end

  it 'should not execute clean task of other projects' do
    define 'foo'
    define 'bar'
    expect { task('foo:clean').invoke }.not_to run_task('bar:clean')
  end
end


describe Project, '#target' do
  before :each do
    @project = define('foo', :layout=>Layout.new)
  end

  it 'should default to target' do
    expect(@project.target).to eql('target')
  end

  it 'should set layout :target' do
    @project.target = 'bar'
    expect(@project.layout.expand(:target)).to point_to_path('bar')
  end

  it 'should come from layout :target' do
    @project.layout[:target] = 'baz'
    expect(@project.target).to eql('baz')
  end

  it 'should be removed in version 1.5 since it was deprecated in version 1.3' do
    expect(Buildr::VERSION).to be < '1.5'
  end
end


describe Project, '#reports' do
  before :each do
    @project = define('foo', :layout=>Layout.new)
  end

  it 'should default to reports' do
    expect(@project.reports).to eql('reports')
  end

  it 'should set layout :reports' do
    @project.reports = 'bar'
    expect(@project.layout.expand(:reports)).to point_to_path('bar')
  end

  it 'should come from layout :reports' do
    @project.layout[:reports] = 'baz'
    expect(@project.reports).to eql('baz')
  end

  it 'should be removed in version 1.5 since it was deprecated in version 1.3' do
    expect(Buildr::VERSION).to be < '1.5'
  end
end


describe Hg do
  describe '#current_branch' do
    it 'should return the correct branch' do
      expect(Hg).to receive(:hg).with('branch').and_return("default\n")
      expect(Hg.send(:current_branch)).to eq('default')
    end
  end

  describe '#uncommitted_files' do
    it 'should return an array of modified files' do
      expect(Hg).to receive(:`).with('hg status').and_return <<-EOF
M abc.txt
M xyz.txt
R hello
R removed
! conflict
A README
? ignore.txt
      EOF
      expect(Hg.uncommitted_files).to include('abc.txt', 'xyz.txt', 'hello', 'README', 'conflict', 'ignore.txt')
    end
  end

  describe '#uncommitted_files' do
    it 'should return an empty array on a clean repository' do
      expect(Hg).to receive(:`).with('hg status').and_return "\n"
      expect(Hg.uncommitted_files).to be_empty
    end
  end

  describe '#remote' do
    it 'should return the aliases of the default remote repositories' do
      expect(Hg).to receive(:hg).with('paths').and_return <<-EOF
default = https://hg.apache.org/repo/my-repo
    EOF
    expect(Hg.send(:remote)).to include('https://hg.apache.org/repo/my-repo')
    end

    it 'should return the aliases of the default push remote repositories' do
      expect(Hg).to receive(:hg).with('paths').and_return <<-EOF
default-push = https://hg.apache.org/repo/my-repo
    EOF
    expect(Hg.send(:remote)).to include('https://hg.apache.org/repo/my-repo')
    end

    it 'should return empty array when no remote repositories found' do
      expect(Hg).to receive(:hg).with('paths').and_return "\n"
      expect(Hg.send(:remote)).to be_empty
    end

    it 'should return empty array when no default-push remote repository found' do
      expect(Hg).to receive(:hg).with('paths').and_return <<-EOF
blah = https://bitbucket.org/sample-repo
      EOF
      expect(Hg.send(:remote)).to be_empty
    end
  end
end # end of Hg


describe Git do
  describe '#uncommitted_files' do
    it 'should return an empty array on a clean repository' do
      expect(Git).to receive(:`).with('git status').and_return <<-EOF
# On branch master
nothing to commit (working directory clean)
      EOF
      expect(Git.uncommitted_files).to be_empty
    end

    it 'should reject a dirty repository, Git 1.4.2 or former' do
      expect(Git).to receive(:`).with('git status').and_return <<-EOF
# On branch master
#
# Changed but not updated:
#   (use "git add <file>..." to update what will be committed)
#   (use "git checkout -- <file>..." to discard changes in working directory)
#
#       modified:   lib/buildr.rb
#       modified:   spec/buildr_spec.rb
#
# Untracked files:
#   (use "git add <file>..." to include in what will be committed)
#
#       error.log
      EOF
      expect(Git.uncommitted_files).to include('lib/buildr.rb', 'error.log')
    end

    it 'should reject a dirty repository, Git 1.4.3 or higher' do
      expect(Git).to receive(:`).with('git status').and_return <<-EOF
# On branch master
# Changed but not updated:
#   (use "git add <file>..." to update what will be committed)
#
#\tmodified:   lib/buildr.rb
#\tmodified:   spec/buildr_spec.rb
#
# Untracked files:
#   (use "git add <file>..." to include in what will be committed)
#
#\terror.log
no changes added to commit (use "git add" and/or "git commit -a")
      EOF
      expect(Git.uncommitted_files).to include('lib/buildr.rb', 'error.log')
    end
  end

  describe '#remote' do
    it 'should return the name of the corresponding remote' do
      expect(Git).to receive(:git).with('config', '--get', 'branch.master.remote').and_return "origin\n"
      expect(Git).to receive(:git).with('remote').and_return "upstream\norigin\n"
      expect(Git.send(:remote, 'master')).to eq('origin')
    end

    it 'should return nil if no remote for the given branch' do
      expect(Git).to receive(:git).with('config', '--get', 'branch.master.remote').and_return "\n"
      expect(Git).not_to receive(:git).with('remote')
      expect(Git.send(:remote, 'master')).to be_nil
    end
  end

  describe '#current_branch' do
    it 'should return the current branch' do
      expect(Git).to receive(:git).with('branch').and_return("  master\n* a-clever-idea\n  ze-great-idea")
      expect(Git.send(:current_branch)).to eq('a-clever-idea')
    end
  end

end # of Git


describe Svn do
  describe '#tag' do
    it 'should remove any existing tag with the same name' do
      allow(Svn).to receive(:repo_url).and_return('http://my.repo.org/foo/trunk')
      allow(Svn).to receive(:copy)
      expect(Svn).to receive(:remove).with('http://my.repo.org/foo/tags/1.0.0', 'Removing old copy')

      Svn.tag '1.0.0'
    end

    it 'should do an svn copy with the release version' do
      allow(Svn).to receive(:repo_url).and_return('http://my.repo.org/foo/trunk')
      allow(Svn).to receive(:remove)
      expect(Svn).to receive(:copy).with(Dir.pwd, 'http://my.repo.org/foo/tags/1.0.0', 'Release 1.0.0')

      Svn.tag '1.0.0'
    end
  end

  # Reference: http://svnbook.red-bean.com/en/1.4/svn.reposadmin.planning.html#svn.reposadmin.projects.chooselayout
  describe '#tag_url' do
    it 'should accept to tag foo/trunk' do
      expect(Svn.tag_url('http://my.repo.org/foo/trunk', '1.0.0')).to eq('http://my.repo.org/foo/tags/1.0.0')
    end

    it 'should accept to tag foo/branches/1.0' do
      expect(Svn.tag_url('http://my.repo.org/foo/branches/1.0', '1.0.1')).to eq('http://my.repo.org/foo/tags/1.0.1')
    end

    it 'should accept to tag trunk/foo' do
      expect(Svn.tag_url('http://my.repo.org/trunk/foo', '1.0.0')).to eq('http://my.repo.org/tags/foo/1.0.0')
    end

    it 'should accept to tag branches/foo/1.0' do
      expect(Svn.tag_url('http://my.repo.org/branches/foo/1.0', '1.0.0')).to eq('http://my.repo.org/tags/foo/1.0.0')
    end

    describe '#repo_url' do
      it 'should extract the SVN URL from svn info' do
        expect(Svn).to receive(:svn).and_return <<-XML
<?xml version="1.0"?>
<info>
<entry
   kind="dir"
   path="."
   revision="724987">
<url>http://my.repo.org/foo/trunk</url>
<repository>
<root>http://my.repo.org</root>
<uuid>13f79535-47bb-0310-9956-ffa450edef68</uuid>
</repository>
<wc-info>
<schedule>normal</schedule>
<depth>infinity</depth>
</wc-info>
<commit
   revision="724955">
<author>boisvert</author>
<date>2008-12-10T01:53:51.240936Z</date>
</commit>
</entry>
</info>
        XML
        expect(Svn.repo_url).to eq('http://my.repo.org/foo/trunk')
      end
    end

  end

end # of Buildr::Svn


describe Release do
  describe 'find' do
    it 'should return HgRelease if project uses Hg' do
      write '.hg/requires'
      expect(Release.find).to be_instance_of(HgRelease)
    end

    it 'should return GitRelease if project uses Git' do
      write '.git/config'
      expect(Release.find).to be_instance_of(GitRelease)
    end

    it 'should return SvnRelease if project uses SVN' do
      write '.svn/xml'
      expect(Release.find).to be_instance_of(SvnRelease)
    end

    # TravisCI seems to place the tmp directory
    # sub-ordinate to git repository so this will not work
    unless ENV['TRAVIS_BUILD_ID']
      it 'should return nil if no known release process' do
        Dir.chdir(Dir.tmpdir) do
          expect(Release.find).to be_nil
        end
      end
    end

    after :each do
      Release.instance_exec { @release = nil }
    end
  end
end


shared_examples_for 'a release process' do

  describe '#make' do
    before do
      write 'buildfile', "VERSION_NUMBER = '1.0.0-SNAPSHOT'"
      # Prevent a real call to a spawned buildr process.
      allow(@release).to receive(:buildr)
      allow(@release).to receive(:check)
      expect(@release).to receive(:sh).with('buildr', '--buildfile', File.expand_path('buildfile.next'),
                                          '--environment', 'development', 'clean', 'upload', 'DEBUG=no')
    end

    it 'should tag a release with the release version' do
      allow(@release).to receive(:update_version_to_next)
      expect(@release).to receive(:tag_release).with('1.0.0')
      @release.make
    end

    it 'should not alter the buildfile before tagging' do
      allow(@release).to receive(:update_version_to_next)
      expect(@release).to receive(:tag_release).with('1.0.0')
      @release.make
      expect(file('buildfile')).to contain('VERSION_NUMBER = "1.0.0"')
    end

    it 'should update the buildfile with the next version number' do
      allow(@release).to receive(:tag_release)
      @release.make
      expect(file('buildfile')).to contain('VERSION_NUMBER = "1.0.1-SNAPSHOT"')
    end

    it 'should keep leading zeros in the next version number' do
      write 'buildfile', "VERSION_NUMBER = '1.0.001-SNAPSHOT'"
      allow(@release).to receive(:tag_release)
      @release.make
      expect(file('buildfile')).to contain('VERSION_NUMBER = "1.0.002-SNAPSHOT"')
    end

    it 'should commit the updated buildfile' do
      allow(@release).to receive(:tag_release)
      @release.make
      expect(file('buildfile')).to contain('VERSION_NUMBER = "1.0.1-SNAPSHOT"')
    end

    it 'should not consider "-rc" as "-SNAPSHOT"' do
      write 'buildfile', "VERSION_NUMBER = '1.0.0-rc1'"
      allow(@release).to receive(:tag_release)
      @release.make
      expect(file('buildfile')).to contain('VERSION_NUMBER = "1.0.0-rc1"')
    end

    it 'should only commit the updated buildfile if the version changed' do
      write 'buildfile', "VERSION_NUMBER = '1.0.0-rc1'"
      expect(@release).not_to receive(:update_version_to_next)
      allow(@release).to receive(:tag_release)
      @release.make
    end
  end

  describe '#resolve_next_version' do

    it 'should increment the version number if SNAPSHOT' do
      expect(@release.send(:resolve_next_version, "1.0.0-SNAPSHOT")).to eq('1.0.1-SNAPSHOT')
    end

    it 'should NOT increment the version number if no SNAPSHOT' do
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('1.0.0')
    end

    it 'should return the version specified by NEXT_VERSION env var' do
      ENV['NEXT_VERSION'] = "version_from_env"
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('version_from_env')
    end

    it 'should return the version specified by next_version' do
      Release.next_version = "ze_next_version"
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('ze_next_version')
    end

    it 'should return the version specified by next_version if next_version is a proc' do
      Release.next_version = lambda {|version| "#{version}++"}
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('1.0.0++')
    end

    it "should return the version specified by 'NEXT_VERSION' env var even if next_version is non nil" do
      ENV['NEXT_VERSION'] = "ze_version_from_env"
      Release.next_version = lambda {|version| "#{version}++"}
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('ze_version_from_env')
    end

    it "should return the version specified by 'next_version' env var even if next_version is non nil" do
      ENV['NEXT_VERSION'] = nil
      ENV['next_version'] = "ze_version_from_env_lowercase"
      Release.next_version = lambda {|version| "#{version}++"}
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('ze_version_from_env_lowercase')
    end
    after {
      Release.next_version = nil
      ENV['NEXT_VERSION'] = nil
      ENV['next_version'] = nil
    }
  end

  describe '#resolve_next_version' do

    it 'should increment the version number if SNAPSHOT' do
      expect(@release.send(:resolve_next_version, "1.0.0-SNAPSHOT")).to eq('1.0.1-SNAPSHOT')
    end

    it 'should NOT increment the version number if no SNAPSHOT' do
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('1.0.0')
    end

    it 'should return the version specified by NEXT_VERSION env var' do
      ENV['NEXT_VERSION'] = "version_from_env"
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('version_from_env')
    end

    it 'should return the version specified by next_version' do
      Release.next_version = "ze_next_version"
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('ze_next_version')
    end

    it 'should return the version specified by next_version if next_version is a proc' do
      Release.next_version = lambda {|version| "#{version}++"}
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('1.0.0++')
    end

    it "should return the version specified by 'NEXT_VERSION' env var even if next_version is non nil" do
      ENV['NEXT_VERSION'] = "ze_version_from_env"
      Release.next_version = lambda {|version| "#{version}++"}
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('ze_version_from_env')
    end

    it "should return the version specified by 'next_version' env var even if next_version is non nil" do
      ENV['NEXT_VERSION'] = nil
      ENV['next_version'] = "ze_version_from_env_lowercase"
      Release.next_version = lambda {|version| "#{version}++"}
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('ze_version_from_env_lowercase')
    end
    after {
      Release.next_version = nil
      ENV['NEXT_VERSION'] = nil
      ENV['next_version'] = nil
    }
  end

  describe '#resolve_next_version' do

    it 'should increment the version number if SNAPSHOT' do
      expect(@release.send(:resolve_next_version, "1.0.0-SNAPSHOT")).to eq('1.0.1-SNAPSHOT')
    end

    it 'should NOT increment the version number if no SNAPSHOT' do
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('1.0.0')
    end

    it 'should return the version specified by NEXT_VERSION env var' do
      ENV['NEXT_VERSION'] = "version_from_env"
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('version_from_env')
    end

    it 'should return the version specified by next_version' do
      Release.next_version = "ze_next_version"
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('ze_next_version')
    end

    it 'should return the version specified by next_version if next_version is a proc' do
      Release.next_version = lambda {|version| "#{version}++"}
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('1.0.0++')
    end

    it "should return the version specified by 'NEXT_VERSION' env var even if next_version is non nil" do
      ENV['NEXT_VERSION'] = "ze_version_from_env"
      Release.next_version = lambda {|version| "#{version}++"}
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('ze_version_from_env')
    end

    it "should return the version specified by 'next_version' env var even if next_version is non nil" do
      ENV['NEXT_VERSION'] = nil
      ENV['next_version'] = "ze_version_from_env_lowercase"
      Release.next_version = lambda {|version| "#{version}++"}
      expect(@release.send(:resolve_next_version, "1.0.0")).to eq('ze_version_from_env_lowercase')
    end
    after {
      Release.next_version = nil
      ENV['NEXT_VERSION'] = nil
      ENV['next_version'] = nil
    }
  end

  describe '#resolve_tag' do
    before do
      allow(@release).to receive(:extract_version).and_return('1.0.0')
    end

    it 'should return tag specified by tag_name' do
      Release.tag_name  = 'first'
      expect(@release.send(:resolve_tag)).to eq('first')
    end

    it 'should use tag returned by tag_name if tag_name is a proc' do
      Release.tag_name  = lambda { |version| "buildr-#{version}" }
      expect(@release.send(:resolve_tag)).to eq('buildr-1.0.0')
    end
    after { Release.tag_name = nil }
  end

  describe '#tag_release' do
    it 'should inform the user' do
      allow(@release).to receive(:extract_version).and_return('1.0.0')
      expect { @release.tag_release('1.0.0') }.to show_info('Tagging release 1.0.0')
    end
  end

  describe '#extract_version' do
    it 'should extract VERSION_NUMBER with single quotes' do
      write 'buildfile', "VERSION_NUMBER = '1.0.0-SNAPSHOT'"
      expect(@release.extract_version).to eq('1.0.0-SNAPSHOT')
    end

    it 'should extract VERSION_NUMBER with double quotes' do
      write 'buildfile', %{VERSION_NUMBER = "1.0.1-SNAPSHOT"}
      expect(@release.extract_version).to eq('1.0.1-SNAPSHOT')
    end

    it 'should extract VERSION_NUMBER without any spaces' do
      write 'buildfile', "VERSION_NUMBER='1.0.2-SNAPSHOT'"
      expect(@release.extract_version).to eq('1.0.2-SNAPSHOT')
    end

    it 'should extract THIS_VERSION as an alternative to VERSION_NUMBER' do
      write 'buildfile', "THIS_VERSION = '1.0.3-SNAPSHOT'"
      expect(@release.extract_version).to eq('1.0.3-SNAPSHOT')
    end

    it 'should complain if no current version number' do
      write 'buildfile', 'define foo'
      expect { @release.extract_version }.to raise_error('Looking for THIS_VERSION = "..." in your Buildfile, none found')
    end
  end

  describe '#with_release_candidate_version' do
    before do
      allow(Buildr.application).to receive(:buildfile).and_return(file('buildfile'))
      write 'buildfile', "THIS_VERSION = '1.1.0-SNAPSHOT'"
    end

    it 'should yield the name of the release candidate buildfile' do
      @release.send :with_release_candidate_version do |new_filename|
        expect(File.read(new_filename)).to eq(%{THIS_VERSION = "1.1.0"})
      end
    end

    it 'should yield a name different from the original buildfile' do
      @release.send :with_release_candidate_version do |new_filename|
        expect(new_filename).not_to point_to_path('buildfile')
      end
    end
  end

  describe '#update_version_to_next' do
    before do
      write 'buildfile', "VERSION_NUMBER = '1.0.5-SNAPSHOT'"
      @release.send(:this_version=, "1.0.5-SNAPSHOT")
    end

    it 'should update the buildfile with a new version number' do
      @release.send :update_version_to_next
      `cp buildfile /tmp/out`
      expect(file('buildfile')).to contain('VERSION_NUMBER = "1.0.6-SNAPSHOT"')
    end

    it 'should commit the new buildfile on the trunk' do
      expect(@release).to receive(:message).and_return('Changed version number to 1.0.1-SNAPSHOT')
      @release.update_version_to_next
    end

    it 'should use the commit message specified by commit_message' do
      Release.commit_message  = 'Here is my custom message'
      expect(@release).to receive(:message).and_return('Here is my custom message')
      @release.update_version_to_next
    end

    it 'should use the commit message returned by commit_message if commit_message is a proc' do
      Release.commit_message  = lambda { |new_version|
        expect(new_version).to eq('1.0.1-SNAPSHOT')
        "increment version number to #{new_version}"
      }
      expect(@release).to receive(:message).and_return('increment version number to 1.0.1-SNAPSHOT')
      @release.update_version_to_next
    end

    it 'should inform the user of the new version' do
      expect { @release.update_version_to_next }.to show_info('Current version is now 1.0.6-SNAPSHOT')
    end
    after { Release.commit_message = nil }
  end


  describe '#check' do
    before { @release.send(:this_version=, "1.0.0-SNAPSHOT") }
    it 'should fail if THIS_VERSION equals the next_version' do
      allow(@release).to receive(:resolve_next_version).and_return('1.0.0-SNAPSHOT')
      expect { @release.check }.to raise_error("The next version can't be equal to the current version 1.0.0-SNAPSHOT.\nUpdate THIS_VERSION/VERSION_NUMBER, specify Release.next_version or use NEXT_VERSION env var")
    end
  end
end


describe HgRelease do
  it_should_behave_like 'a release process'

  before do
    write 'buildfile', "VERSION_NUMBER = '1.0.0-SNAPSHOT'"
    @release = HgRelease.new
    allow(Hg).to receive(:hg)
    allow(Hg).to receive(:remote).and_return('https://bitbucket.org/sample-repo')
    allow(Hg).to receive(:current_branch).and_return('default')
  end

  describe '#applies_to?' do
    it 'should reject a non-hg repo' do
      Dir.chdir(Dir.tmpdir) do
        expect(HgRelease.applies_to?).to be_falsey
      end
    end

    it 'should accept a hg repo' do
      FileUtils.mkdir '.hg'
      FileUtils.touch File.join('.hg', 'requires')
      expect(HgRelease.applies_to?).to be_truthy
    end
  end

  describe '#check' do
    before do
      @release = HgRelease.new
      @release.send(:this_version=, '1.0.0-SNAPSHOT')
    end

    it 'should accept a clean repo' do
      expect(Hg).to receive(:uncommitted_files).and_return([])
      expect(Hg).to receive(:remote).and_return(["http://bitbucket.org/sample-repo"])
      expect { @release.check }.not_to raise_error
    end

    it 'should reject a dirty repo' do
      expect(Hg).to receive(:uncommitted_files).and_return(['dirty_file.txt'])
      expect { @release.check }.to raise_error(RuntimeError, /uncommitted files/i)
    end

    it 'should reject a local branch not tracking a remote repo' do
      expect(Hg).to receive(:uncommitted_files).and_return([])
      expect(Hg).to receive(:remote).and_return([])
      expect{ @release.check }.to raise_error(RuntimeError,
        "You are releasing from a local branch that does not track a remote!")
    end
  end
end


describe GitRelease do
  it_should_behave_like 'a release process'

  before do
    write 'buildfile', "VERSION_NUMBER = '1.0.0-SNAPSHOT'"
    @release = GitRelease.new
    allow(Git).to receive(:git)
    allow(Git).to receive(:current_branch).and_return('master')
  end

  describe '#applies_to?' do

    # TravisCI seems to place the tmp directory
    # sub-ordinate to git repository so this will not work
    unless ENV['TRAVIS_BUILD_ID']
      it 'should reject a non-git repo' do
        Dir.chdir(Dir.tmpdir) do
          expect(GitRelease.applies_to?).to be_falsey
        end
      end
    end

    it 'should accept a git repo' do
      FileUtils.mkdir '.git'
      FileUtils.touch File.join('.git', 'config')
      expect(GitRelease.applies_to?).to be_truthy
    end
  end

  describe '#check' do
    before do
      @release = GitRelease.new
      @release.send(:this_version=, '1.0.0-SNAPSHOT')
    end

    it 'should accept a clean repository' do
      expect(Git).to receive(:`).with('git status').and_return <<-EOF
# On branch master
nothing to commit (working directory clean)
      EOF
      expect(Git).to receive(:remote).and_return('master')
      expect { @release.check }.not_to raise_error
    end

    it 'should reject a dirty repository' do
      expect(Git).to receive(:`).with('git status').and_return <<-EOF
# On branch master
# Untracked files:
#   (use "git add <file>..." to include in what will be committed)
#
#       foo.temp
EOF
      expect { @release.check }.to raise_error(RuntimeError, /uncommitted files/i)
    end

    it 'should reject a repository not tracking remote branch' do
      expect(Git).to receive(:uncommitted_files).and_return([])
      expect(Git).to receive(:remote).and_return(nil)
      expect{ @release.check }.to raise_error(RuntimeError,
        "You are releasing from a local branch that does not track a remote!")
    end
  end

  describe '#tag_release' do
    before do
      @release = GitRelease.new
      allow(@release).to receive(:extract_version).and_return('1.0.1')
      allow(@release).to receive(:resolve_tag).and_return('TEST_TAG')
      allow(Git).to receive(:git).with('tag', '-a', 'TEST_TAG', '-m', '[buildr] Cutting release TEST_TAG')
      allow(Git).to receive(:git).with('push', 'origin', 'tag', 'TEST_TAG')
      allow(Git).to receive(:commit)
      allow(Git).to receive(:push)
      allow(Git).to receive(:remote).and_return('origin')
    end

    it 'should delete any existing tag with the same name' do
      expect(Git).to receive(:git).with('tag', '-d', 'TEST_TAG')
      expect(Git).to receive(:git).with('push', 'origin', ':refs/tags/TEST_TAG')
      @release.tag_release 'TEST_TAG'
    end

    it 'should commit the buildfile before tagging' do
      expect(Git).to receive(:commit).with(File.basename(Buildr.application.buildfile.to_s), "Changed version number to 1.0.1")
      @release.tag_release 'TEST_TAG'
    end

    it 'should push the tag if a remote is tracked' do
      expect(Git).to receive(:git).with('tag', '-d', 'TEST_TAG')
      expect(Git).to receive(:git).with('push', 'origin', ':refs/tags/TEST_TAG')
      expect(Git).to receive(:git).with('tag', '-a', 'TEST_TAG', '-m', '[buildr] Cutting release TEST_TAG')
      expect(Git).to receive(:git).with('push', 'origin', 'tag',  'TEST_TAG')
      @release.tag_release 'TEST_TAG'
    end

    it 'should NOT push the tag if no remote is tracked' do
      allow(Git).to receive(:remote).and_return(nil)
      expect(Git).not_to receive(:git).with('push', 'origin', 'tag',  'TEST_TAG')
      @release.tag_release 'TEST_TAG'
    end
  end
end


describe SvnRelease do
  it_should_behave_like 'a release process'

  before do
    write 'buildfile', "VERSION_NUMBER = '1.0.0-SNAPSHOT'"
    @release = SvnRelease.new
    allow(Svn).to receive(:svn)
    allow(Svn).to receive(:repo_url).and_return('http://my.repo.org/foo/trunk')
    allow(Svn).to receive(:tag)
  end

  describe '#applies_to?' do
    it 'should reject a non-git repo' do
      expect(SvnRelease.applies_to?).to be_falsey
    end

    it 'should accept a git repo' do
      FileUtils.touch '.svn'
      expect(SvnRelease.applies_to?).to be_truthy
    end
  end

  describe '#check' do
    before do
      allow(Svn).to receive(:uncommitted_files).and_return([])
      @release = SvnRelease.new
      @release.send(:this_version=, "1.0.0-SNAPSHOT")
    end

    it 'should accept to release from the trunk' do
      allow(Svn).to receive(:repo_url).and_return('http://my.repo.org/foo/trunk')
      expect { @release.check }.not_to raise_error
    end

    it 'should accept to release from a branch' do
      allow(Svn).to receive(:repo_url).and_return('http://my.repo.org/foo/branches/1.0')
      expect { @release.check }.not_to raise_error
    end

    it 'should reject releasing from a tag' do
      allow(Svn).to receive(:repo_url).and_return('http://my.repo.org/foo/tags/1.0.0')
      expect { @release.check }.to raise_error(RuntimeError, "SVN URL must contain 'trunk' or 'branches/...'")
    end

    it 'should reject a non standard repository layout' do
      allow(Svn).to receive(:repo_url).and_return('http://my.repo.org/foo/bar')
      expect { @release.check }.to raise_error(RuntimeError, "SVN URL must contain 'trunk' or 'branches/...'")
    end

    it 'should reject an uncommitted file' do
      allow(Svn).to receive(:repo_url).and_return('http://my.repo.org/foo/trunk')
      allow(Svn).to receive(:uncommitted_files).and_return(['foo.rb'])
      expect { @release.check }.to raise_error(RuntimeError,
        "Uncommitted files violate the First Principle Of Release!\n" +
        "foo.rb")
    end
  end
end
