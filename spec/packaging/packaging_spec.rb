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
require File.expand_path(File.join(File.dirname(__FILE__), 'packaging_helper'))

describe Project, '#group' do
  it 'should default to project name' do
    desc 'My Project'
    expect(define('foo').group).to eql('foo')
  end

  it 'should be settable' do
    expect(define('foo', :group=>'bar').group).to eql('bar')
  end

  it 'should inherit from parent project' do
    define('foo', :group=>'groupie') { define 'bar' }
    expect(project('foo:bar').group).to eql('groupie')
  end
end

describe Project, '#version' do
  it 'should default to nil' do
    expect(define('foo').version).to be_nil
  end

  it 'should be settable' do
    expect(define('foo', :version=>'2.1').version).to eql('2.1')
  end

  it 'should inherit from parent project' do
    define('foo', :version=>'2.1') { define 'bar' }
    expect(project('foo:bar').version).to eql('2.1')
  end
end

describe Project, '#id' do
  it 'should be same as project name' do
    expect(define('foo').id).to eql('foo')
  end

  it 'should replace colons with dashes' do
    define('foo', :version=>'2.1') { define 'bar' }
    expect(project('foo:bar').id).to eql('foo-bar')
  end

  it 'should not be settable' do
    expect { define 'foo', :id=>'bar' }.to raise_error(NoMethodError)
  end
end


describe Project, '#package' do
  it 'should default to id from project' do
    define('foo', :version=>'1.0') do
      expect(package(:jar).id).to eql('foo')
    end
  end

  it 'should default to composed id for nested projects' do
    define('foo', :version=>'1.0') do
      define 'bar' do
        expect(package(:jar).id).to eql('foo-bar')
      end
    end
  end

  it 'should take id from option if specified' do
    define 'foo', :version=>'1.0' do
      expect(package(:jar, :id=>'bar').id).to eql('bar')
      define 'bar' do
        expect(package(:jar, :id=>'baz').id).to eql('baz')
      end
    end
  end

  it 'should default to group from project' do
    define 'foo', :version=>'1.0' do
      expect(package(:jar).group).to eql('foo')
      define 'bar' do
        expect(package(:jar).group).to eql('foo')
      end
    end
  end

  it 'should take group from option if specified' do
    define 'foo', :version=>'1.0' do
      expect(package(:jar, :group=>'foos').group).to eql('foos')
      define 'bar' do
        expect(package(:jar, :group=>'bars').group).to eql('bars')
      end
    end
  end

  it 'should default to version from project' do
    define 'foo', :version=>'1.0' do
      expect(package(:jar).version).to eql('1.0')
      define 'bar' do
        expect(package(:jar).version).to eql('1.0')
      end
    end
  end

  it 'should take version from option if specified' do
    define 'foo', :version=>'1.0' do
      expect(package(:jar, :version=>'1.1').version).to eql('1.1')
      define 'bar' do
        expect(package(:jar, :version=>'1.2').version).to eql('1.2')
      end
    end
  end

  it 'should accept package type as first argument' do
    define 'foo', :version=>'1.0' do
      expect(package(:war).type).to eql(:war)
      define 'bar' do
        expect(package(:jar).type).to eql(:jar)
      end
    end
  end

  it 'should support optional type' do
    define 'foo', :version=>'1.0' do
      expect(package.type).to eql(:zip)
      expect(package(:classifier=>'srcs').type).to eql(:zip)
    end
    define 'bar', :version=>'1.0' do
      compile.using :javac
      expect(package(:classifier=>'srcs').type).to eql(:jar)
    end
  end

  it 'should assume :zip package type unless specified' do
    define 'foo', :version=>'1.0' do
      expect(package.type).to eql(:zip)
      define 'bar' do
        expect(package.type).to eql(:zip)
      end
    end
  end

  it 'should infer packaging type from compiler' do
    define 'foo', :version=>'1.0' do
      compile.using :javac
      expect(package.type).to eql(:jar)
    end
  end

  it 'should fail if packaging not supported' do
    expect { define('foo') { package(:weirdo) } }.to raise_error(RuntimeError, /Don't know how to create a package/)
  end

  it 'should call package_as_foo when using package(:foo)' do
    class Buildr::Project
      def package_as_foo(file_name)
        file(file_name) do |t|
          mkdir_p File.dirname(t.to_s)
          File.open(t.to_s, 'w') {|f| f.write('foo') }
        end
      end
    end
    define('foo', :version => '1.0') do |project|
      package(:foo).invoke
      expect(package(:foo)).to exist
      expect(package(:foo)).to contain('foo')
    end
  end

  it 'should allow to respec package(:sources) using package_as_sources_spec()' do
    class Buildr::Project
      def package_as_sources_spec(spec)
        spec.merge({ :type=>:jar, :classifier=>'sources' })
      end
    end
    define('foo', :version => '1.0') do
      expect(package(:sources).type).to eql(:jar)
      expect(package(:sources).classifier).to eql('sources')
    end
  end

  it 'should produce different packages for different specs' do
    class Buildr::Project
      def package_as_foo(file_name)
        file(file_name)
      end

      def package_as_foo_spec(spec)
        spec.merge(:type => :zip)
      end

      def package_as_bar(file_name)
        file(file_name)
      end

      def package_as_bar_spec(spec)
        spec.merge(:type => :zip, :classifier => "foobar")
      end

    end
    define('foo', :version => '1.0') do
      expect(package(:foo).type).to eql(:zip)
      expect(package(:foo).classifier).to be_nil
      expect(package(:bar).type).to eql(:zip)
      expect(package(:bar).classifier).to eql('foobar')
      expect(package(:foo).equal?(package(:bar))).to be_falsey
    end
  end

  it 'should default to no classifier' do
    define 'foo', :version=>'1.0' do
      expect(package.classifier).to be_nil
      define 'bar' do
        expect(package.classifier).to be_nil
      end
    end
  end

  it 'should accept classifier from option' do
    define 'foo', :version=>'1.0' do
      expect(package(:classifier=>'srcs').classifier).to eql('srcs')
      define 'bar' do
        expect(package(:classifier=>'docs').classifier).to eql('docs')
      end
    end
  end

  it 'should return a file task' do
    define('foo', :version=>'1.0') { package(:jar) }
    expect(project('foo').package(:jar)).to be_kind_of(Rake::FileTask)
  end

  it 'should return a task that acts as artifact' do
    define('foo', :version=>'1.0') { package(:jar) }
    expect(project('foo').package(:jar)).to respond_to(:to_spec)
    expect(project('foo').package(:jar).to_spec).to eql('foo:foo:jar:1.0')
  end

  it 'should create different tasks for each spec' do
    define 'foo', :version=>'1.0' do
      package(:jar)
      package(:war)
      package(:jar, :id=>'bar')
      package(:jar, :classifier=>'srcs')
      package(:jar, :classifier=>'doc')
    end
    expect(project('foo').packages.uniq.size).to be(5)
  end

  it 'should create different tasks for package with different ids' do
    define 'foo', :version=>'1.0' do
      package(:jar, :id=>'bar')
      package(:jar)
    end
    expect(project('foo').packages.uniq.size).to be(2)
  end

  it 'should create different tasks for package with classifier' do
    define 'foo', :version=>'1.0' do
      package(:jar)
      package(:jar, :classifier=>'foo')
    end
    expect(project('foo').packages.uniq.size).to be(2)
  end

  it 'should not create multiple packages for the same spec' do
    define 'foo', :version=>'1.0' do
      package(:war)
      package(:war)
      package(:jar, :id=>'bar')
      package(:jar, :id=>'bar')
      package(:jar, :id=>'baz')
    end
    expect(project('foo').packages.uniq.size).to be(3)
  end

  it 'should create different tasks for specs with matching type' do
    define 'foo', :version=>'1.0' do
      javadoc("foo").into( "foo" )
      package(:javadoc)
      package(:zip)
    end
    expect(project('foo').packages.uniq.size).to be(2)
  end

  it 'should return the same task for subsequent calls' do
    define 'foo', :version=>'1.0' do
      expect(package).to eql(package)
      expect(package(:jar, :classifier=>'resources')).to be(package(:jar, :classifier=>'resources'))
    end
  end

  it 'should return a packaging task even if file already exists' do
    write 'target/foo-1.0.zip', ''
    define 'foo', :version=>'1.0' do
      expect(package).to be_kind_of(ZipTask)
    end
  end

  it 'should register task as artifact' do
    define 'foo', :version=>'1.0' do
      package(:jar, :id=>'bar')
      package(:war)
    end
    expect(project('foo').packages).to eql(artifacts('foo:bar:jar:1.0', 'foo:foo:war:1.0'))
  end

  it 'should create in target path' do
    define 'foo', :version=>'1.0' do
      expect(package(:war)).to point_to_path('target/foo-1.0.war')
      expect(package(:jar, :id=>'bar')).to point_to_path('target/bar-1.0.jar')
      expect(package(:zip, :classifier=>'srcs')).to point_to_path('target/foo-1.0-srcs.zip')
    end
  end

  it 'should create prerequisite for package task' do
    define 'foo', :version=>'1.0' do
      package(:war)
      package(:jar, :id=>'bar')
      package(:jar, :classifier=>'srcs')
    end
    expect(project('foo').task('package').prerequisites).to include(*project('foo').packages)
  end

  it 'should create task requiring a build' do
    define 'foo', :version=>'1.0' do
      expect(package(:war).prerequisites).to include(build)
      expect(package(:jar, :id=>'bar').prerequisites).to include(build)
      expect(package(:jar, :classifier=>'srcs').prerequisites).to include(build)
    end
  end

  it 'should create a POM artifact in target directory' do
    define 'foo', :version=>'1.0' do
      expect(package.pom).to be(artifact('foo:foo:pom:1.0'))
      expect(package.pom.to_s).to point_to_path('target/foo-1.0.pom')
    end
  end

  it 'should create POM artifact ignoring classifier' do
    define 'foo', :version=>'1.0' do
      expect(package(:jar, :classifier=>'srcs').pom).to be(artifact('foo:foo:pom:1.0'))
    end
  end

  it 'should create POM artifact that creates its own POM' do
    define('foo', :group=>'bar', :version=>'1.0') { package(:jar, :classifier=>'srcs') }
    pom = project('foo').packages.first.pom
    pom.invoke
    expect(read(pom.to_s)).to eql(<<-POM
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>bar</groupId>
  <artifactId>foo</artifactId>
  <version>1.0</version>
</project>
POM
    )
  end

  it 'should not require downloading artifact or POM' do
    #task('artifacts').instance_eval { @actions.clear }
    define('foo', :group=>'bar', :version=>'1.0') { package(:jar) }
    expect { task('artifacts').invoke }.not_to raise_error
  end

  describe "existing package access" do
    it "should return the same instance for identical optionless invocations" do
      define 'foo', :version => '1.0' do
        expect(package(:zip)).to equal(package(:zip))
      end
      expect(project('foo').packages.size).to eq(1)
    end

    it "should return the exactly matching package identical invocations with options" do
      define 'foo', :version => '1.0' do
        package(:zip, :id => 'src')
        package(:zip, :id => 'bin')
      end
      expect(project('foo').package(:zip, :id => 'src')).to equal(project('foo').packages.first)
      expect(project('foo').package(:zip, :id => 'bin')).to equal(project('foo').packages.last)
      expect(project('foo').packages.size).to eq(2)
    end

    it "should return the first of the same type for subsequent optionless invocations" do
      define 'foo', :version => '1.0' do
        package(:zip, :file => 'override.zip')
        package(:jar, :file => 'another.jar')
      end
      expect(project('foo').package(:zip).name).to eq('override.zip')
      expect(project('foo').package(:jar).name).to eq('another.jar')
      expect(project('foo').packages.size).to eq(2)
    end
  end
end

describe Project, '#package file' do
  it 'should be a file task' do
    define 'foo' do
      expect(package(:zip, :file=>'foo.zip')).to be_kind_of(Rake::FileTask)
    end
  end

  it 'should not require id, project or version' do
    define 'foo', :group=>nil do
      expect { package(:zip, :file=>'foo.zip') }.not_to raise_error
      expect { package(:zip, :file=>'bar.zip', :id=>'error') }.to raise_error /no such option: id/
      expect { package(:zip, :file=>'bar.zip', :group=>'error') }.to raise_error /no such option: group/
      expect { package(:zip, :file=>'bar.zip', :version=>'error') }.to raise_error /no such option: version/
    end
  end

  it 'should not provide project or version' do
    define 'foo' do
      package(:zip, :file=>'foo.zip').tap do |pkg|
        expect(pkg).not_to respond_to(:group)
        expect(pkg).not_to respond_to(:version)
      end
    end
  end

  it 'should provide packaging type' do
    define 'foo', :version=>'1.0' do
      zip = package(:zip, :file=>'foo.zip')
      jar = package(:jar, :file=>'bar.jar')
      expect(zip.type).to eql(:zip)
      expect(jar.type).to eql(:jar)
    end
  end

  it 'should assume packaging type from extension if unspecified' do
    define 'foo', :version=>'1.0' do
      expect(package(:file=>'foo.zip').class).to be(Buildr::ZipTask)
      define 'bar' do
        expect(package(:file=>'bar.jar').class).to be(Buildr::Packaging::Java::JarTask)
      end
    end
  end

  it 'should support different packaging types' do
    define 'foo', :version=>'1.0' do
      expect(package(:jar, :file=>'foo.jar').class).to be(Buildr::Packaging::Java::JarTask)
    end
    define 'bar' do
      expect(package(:type=>:war, :file=>'bar.war').class).to be(Buildr::Packaging::Java::WarTask)
    end
  end

  it 'should fail if packaging not supported' do
    expect { define('foo') { package(:weirdo, :file=>'foo.zip') } }.to raise_error(RuntimeError, /Don't know how to create a package/)
  end

  it 'should create different tasks for each file' do
    define 'foo', :version=>'1.0' do
      package(:zip, :file=>'foo.zip')
      package(:jar, :file=>'foo.jar')
    end
    expect(project('foo').packages.uniq.size).to be(2)
  end

  it 'should return the same task for subsequent calls' do
    define 'foo', :version=>'1.0' do
      expect(package(:zip, :file=>'foo.zip')).to eql(package(:file=>'foo.zip'))
    end
  end

  it 'should point to specified file' do
    define 'foo', :version=>'1.0' do
      expect(package(:zip, :file=>'foo.zip')).to point_to_path('foo.zip')
      expect(package(:zip, :file=>'target/foo-1.0.zip')).to point_to_path('target/foo-1.0.zip')
    end
  end

  it 'should create prerequisite for package task' do
    define 'foo', :version=>'1.0' do
      package(:zip, :file=>'foo.zip')
    end
    expect(project('foo').task('package').prerequisites).to include(*project('foo').packages)
  end

  it 'should create task requiring a build' do
    define 'foo', :version=>'1.0' do
      expect(package(:zip, :file=>'foo.zip').prerequisites).to include(build)
    end
  end

  it 'should create specified file during build' do
    define 'foo', :version=>'1.0' do
      package(:zip, :file=>'foo.zip')
    end
    expect { project('foo').task('package').invoke }.to change { File.exist?('foo.zip') }.to(true)
  end

  it 'should do nothing for installation/upload' do
    define 'foo', :version=>'1.0' do
      package(:zip, :file=>'foo.zip')
    end
    expect do
      task('install').invoke
      task('upload').invoke
      task('uninstall').invoke
    end.not_to raise_error
  end

end

describe Rake::Task, ' package' do
  it 'should be local task' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    in_original_dir project('foo:bar').base_dir do
      task('package').invoke
      expect(project('foo').package).not_to exist
      expect(project('foo:bar').package).to exist
    end
  end

  it 'should be recursive task' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    task('package').invoke
    expect(project('foo').package).to exist
    expect(project('foo:bar').package).to exist
  end

  it 'should create package in target directory' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    task('package').invoke
    expect(FileList['**/target/*.zip'].map.sort).to eq(['bar/target/foo-bar-1.0.zip', 'target/foo-1.0.zip'])
  end
end

describe Rake::Task, ' install' do
  it 'should be local task' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    in_original_dir project('foo:bar').base_dir do
      task('install').invoke
      artifacts('foo:foo:zip:1.0', 'foo:foo:pom:1.0').each { |t| expect(t).not_to exist }
      artifacts('foo:foo-bar:zip:1.0', 'foo:foo-bar:pom:1.0').each { |t| expect(t).to exist }
    end
  end

  it 'should be recursive task' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    task('install').invoke
    artifacts('foo:foo:zip:1.0', 'foo:foo:pom:1.0', 'foo:foo-bar:zip:1.0', 'foo:foo-bar:pom:1.0').each { |t| expect(t).to exist }
  end

  it 'should create package in local repository' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    task('install').invoke
    expect(FileList[repositories.local + '/**/*'].reject { |f| File.directory?(f) }.sort).to eq([
      File.expand_path('foo/foo/1.0/foo-1.0.zip', repositories.local),
      File.expand_path('foo/foo/1.0/foo-1.0.pom', repositories.local),
      File.expand_path('foo/foo-bar/1.0/foo-bar-1.0.zip', repositories.local),
      File.expand_path('foo/foo-bar/1.0/foo-bar-1.0.pom', repositories.local)].sort)
  end
end

describe Rake::Task, ' uninstall' do
  it 'should be local task' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    task('install').invoke
    in_original_dir project('foo:bar').base_dir do
      task('uninstall').invoke
      expect(FileList[repositories.local + '/**/*'].reject { |f| File.directory?(f) }.sort).to eq([
        File.expand_path('foo/foo/1.0/foo-1.0.zip', repositories.local),
        File.expand_path('foo/foo/1.0/foo-1.0.pom', repositories.local)].sort)
    end
  end

  it 'should be recursive task' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    task('install').invoke
    task('uninstall').invoke
    expect(FileList[repositories.local + '/**/*'].reject { |f| File.directory?(f) }.sort).to be_empty
  end
end

describe Rake::Task, ' upload' do
  before do
    repositories.release_to = URI.escape("file://#{File.expand_path('remote')}")
  end

  it 'should be local task' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    in_original_dir project('foo:bar').base_dir do
      expect { task('upload').invoke }.to run_task('foo:bar:upload').but_not('foo:upload')
    end
  end

  it 'should be recursive task' do
    define 'foo', :version=>'1.0' do
      package
      define('bar') { package }
    end
    expect { task('upload').invoke }.to run_tasks('foo:upload', 'foo:bar:upload')
  end

  it 'should upload artifact and POM' do
    define('foo', :version=>'1.0') { package :jar }
    task('upload').invoke
    { 'remote/foo/foo/1.0/foo-1.0.jar'=>project('foo').package(:jar),
      'remote/foo/foo/1.0/foo-1.0.pom'=>project('foo').package(:jar).pom }.each do |upload, package|
      expect(read(upload)).to eql(read(package))
    end
  end

  it 'should not upload twice the pom when artifacts are uploaded from a project' do
    write 'src/main/java/Foo.java', 'public class Foo {}'
    repositories.release_to = 'sftp://buildr.apache.org/repository/noexist/base'
    define 'foo' do
      project.group = "attached"
      project.version = "1.0"
      package(:jar)
      package(:sources)
    end
     expect(URI).to receive(:upload).exactly(:once).
         with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/attached/foo/1.0/foo-1.0-sources.jar'), project("foo").package(:sources).to_s, anything)
     expect(URI).to receive(:upload).exactly(:once).
         with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/attached/foo/1.0/foo-1.0.jar'), project("foo").package(:jar).to_s, anything)
     expect(URI).to receive(:upload).exactly(:once).
        with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/attached/foo/1.0/foo-1.0.pom'), project("foo").package(:jar).pom.to_s, anything)
     verbose(false) { project("foo").upload.invoke }
  end

  it 'should upload signatures for artifact and POM' do
    define('foo', :version=>'1.0') { package :jar }
    task('upload').invoke
    { 'remote/foo/foo/1.0/foo-1.0.jar'=>project('foo').package(:jar),
      'remote/foo/foo/1.0/foo-1.0.pom'=>project('foo').package(:jar).pom }.each do |upload, package|
      expect(read("#{upload}.md5").split.first).to eql(Digest::MD5.hexdigest(read(package, "rb")))
      expect(read("#{upload}.sha1").split.first).to eql(Digest::SHA1.hexdigest(read(package, "rb")))
    end
  end
end

describe Packaging, 'zip' do
  it_should_behave_like 'packaging'
  before { @packaging = :zip }

  it 'should not include META-INF directory' do
    define('foo', :version=>'1.0') { package(:zip) }
    project('foo').package(:zip).invoke
    Zip::File.open(project('foo').package(:zip).to_s) do |zip|
      expect(zip.entries.map(&:to_s)).not_to include('META-INF/')
    end
  end
end

describe Packaging, ' tar' do
  before { @packaging = :tar }
  it_should_behave_like 'packaging'
end

describe Packaging, ' tgz' do
  before { @packaging = :tgz }
  it_should_behave_like 'packaging'
end
