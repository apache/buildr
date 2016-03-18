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
require 'fileutils'

describe Artifact do
  before do
    Buildr.repositories.instance_eval do
      @local = @remote = @release_to = nil
    end
    @spec = { :group=>'com.example', :id=>'library', :type=>:jar, :version=>'2.0' }
    @artifact = artifact(@spec)
    @classified = artifact(@spec.merge(:classifier=>'all'))
    @snapshot = artifact(@spec.merge({ :version=>'2.1-SNAPSHOT' }))
  end


  it 'should act as one' do
    expect(@artifact).to respond_to(:to_spec)
  end

  it 'should have an artifact identifier' do
    expect(@artifact.id).to eql('library')
  end

  it 'should have a group identifier' do
    expect(@artifact.group).to eql('com.example')
  end

  it 'should have a version number' do
    expect(@artifact.version).to eql('2.0')
  end

  it 'should know if it is a snapshot' do
    expect(@artifact).not_to be_snapshot
    expect(@classified).not_to be_snapshot
    expect(@snapshot).to be_snapshot
  end

  it 'should have a file type' do
    expect(@artifact.type).to eql(:jar)
  end

  it 'should understand classifier' do
    expect(@artifact.classifier).to be_nil
    expect(@classified.classifier).to eql('all')
  end

  it 'should return hash specification' do
    expect(@artifact.to_hash).to eq(@spec)
    expect(@artifact.to_spec_hash).to eq(@spec)
    expect(@classified.to_hash).to eq(@spec.merge(:classifier=>'all'))
  end

  it 'should return string specification' do
    expect(@artifact.to_spec).to eql('com.example:library:jar:2.0')
    expect(@classified.to_spec).to eql('com.example:library:jar:all:2.0')
  end

  it 'should have associated POM artifact' do
    expect(@artifact.pom.to_hash).to eq(@artifact.to_hash.merge(:type=>:pom))
  end

  it 'should have one POM artifact for all classifiers' do
    expect(@classified.pom.to_hash).to eq(@classified.to_hash.merge(:type=>:pom).except(:classifier))
  end

  it 'should have associated sources artifact' do
    expect(@artifact.sources_artifact.to_hash).to eq(@artifact.to_hash.merge(:classifier=>'sources'))
  end

  it 'should have associated javadoc artifact' do
    expect(@artifact.javadoc_artifact.to_hash).to eq(@artifact.to_hash.merge(:classifier=>'javadoc'))
  end

  it 'should download file if file does not exist' do
    expect { @artifact.invoke }.to raise_error(Exception, /No remote repositories/)
    expect { @classified.invoke }.to raise_error(Exception, /No remote repositories/)
  end

  it 'should not download file if file exists' do
    write repositories.locate(@artifact)
    expect { @artifact.invoke }.not_to raise_error
    write repositories.locate(@classified)
    expect { @classified.invoke }.not_to raise_error
  end

  it 'should handle lack of POM gracefully' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).twice { |*args| raise URI::NotFoundError if args[0].to_s.end_with?('.pom') }
    expect { @artifact.invoke }.not_to raise_error
  end

  it 'should pass if POM provided' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    @artifact.pom.enhance { |task| write task.name, @artifact.pom_xml.call }
    write repositories.locate(@artifact)
    expect { @artifact.invoke }.not_to raise_error
  end

  it 'should pass if POM not required' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    class << @artifact ; def pom() ; end ; end
    write repositories.locate(@artifact)
    expect { @artifact.invoke }.not_to raise_error
  end

  it 'should not download file if dry-run' do
    dryrun do
      expect { @artifact.invoke }.not_to raise_error
      expect { @classified.invoke }.not_to raise_error
    end
  end

  it 'should resolve to path in local repository' do
    expect(@artifact.to_s).to eq(File.join(repositories.local, 'com/example/library/2.0/library-2.0.jar'))
    expect(@classified.to_s).to eq(File.join(repositories.local, 'com/example/library/2.0/library-2.0-all.jar'))
  end

  it 'should return a list of all registered artifact specifications' do
    define('foo', :version=>'1.0') { package :jar }
    expect(Artifact.list).to include(@artifact.to_spec)
    expect(Artifact.list).to include(@classified.to_spec)
    expect(Artifact.list).to include('foo:foo:jar:1.0')
  end

  it 'should accept user-defined string content' do
    a = artifact(@spec)
    a.content 'foo'
    install a
    expect { install.invoke }.to change { File.exist?(a.to_s) && File.exist?(repositories.locate(a)) }.to(true)
    expect(read(repositories.locate(a))).to eql('foo')
  end
end


describe Repositories, 'local' do
  before do
    Buildr.repositories.instance_eval do
      @local = @remote = @release_to = nil
    end
  end

  it 'should default to .m2 path' do
    # For convenience, sandbox actually sets the local repository to a temp directory
    repositories.local = nil
    expect(repositories.local).to eql(File.expand_path('.m2/repository', ENV['HOME']))
  end

  it 'should be settable' do
    repositories.local = '.m2/local'
    expect(repositories.local).to eql(File.expand_path('.m2/local'))
  end

  it 'should reset to default' do
    repositories.local = '.m2/local'
    repositories.local = nil
    expect(repositories.local).to eql(File.expand_path('~/.m2/repository'))
  end

  it 'should locate file from string specification' do
    repositories.local = nil
    expect(repositories.locate('com.example:library:jar:2.0')).to eql(
      File.expand_path('~/.m2/repository/com/example/library/2.0/library-2.0.jar'))
  end

  it 'should locate file from hash specification' do
    repositories.local = nil
    expect(repositories.locate(:group=>'com.example', :id=>'library', :version=>'2.0')).to eql(
      File.expand_path('~/.m2/repository/com/example/library/2.0/library-2.0.jar'))
  end

  it 'should load path from settings file' do
    write 'home/.buildr/settings.yaml', <<-YAML
    repositories:
      local: my_repo
    YAML
    expect(repositories.local).to eql(File.expand_path('my_repo'))
  end

  it 'should not override custom install methods defined when extending an object' do
    class MyOwnInstallTask

      attr_accessor :result

      def install
        result = true
      end

    end
    task = MyOwnInstallTask.new
    task.result = "maybe"
    task.extend ActsAsArtifact
    task.install
    expect(task.result).to be_truthy
  end
end


describe Repositories, 'remote' do
  before do
    Buildr.repositories.instance_eval do
      @local = @remote = @release_to = nil
    end

    @repos = [ 'http://www.ibiblio.org/maven2', 'http://repo1.maven.org/maven2' ]
  end

  it 'should be empty initially' do
    expect(repositories.remote).to be_empty
  end

  it 'should be settable' do
    repositories.remote = @repos.first
    expect(repositories.remote).to eql([@repos.first])
  end

  it 'should be settable from array' do
    repositories.remote = @repos
    expect(repositories.remote).to eql(@repos)
  end

  it 'should add and return repositories in order' do
    @repos.each { |url| repositories.remote << url }
    expect(repositories.remote).to eql(@repos)
  end

  it 'should be used to download artifact' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).twice { |uri, target, options| write target }
    expect { artifact('com.example:library:jar:2.0').invoke }.
      to change { File.exist?(File.join(repositories.local, 'com/example/library/2.0/library-2.0.jar')) }.to(true)
  end

  it 'should lookup in array order' do
    repositories.remote = [ 'http://buildr.apache.org/repository/noexist', 'http://example.org' ]
    order = ['com', 'org']
    allow(URI).to receive(:download) do |uri, target, options|
      order.shift if order.first && uri.to_s[order.first]
      fail URI::NotFoundError unless order.empty?
      write target
    end
    expect { artifact('com.example:library:jar:2.0').invoke }.to change { order.empty? }
  end

  it 'should fail if artifact not found' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).once.ordered { fail URI::NotFoundError }
    expect { artifact('com.example:library:jar:2.0').invoke }.to raise_error(RuntimeError, /Failed to download/)
    expect(File.exist?(File.join(repositories.local, 'com/example/library/2.0/library-2.0.jar'))).to be_falsey
  end

  it 'should support artifact classifier' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).once { |uri, target, options| write target }
    expect { artifact('com.example:library:jar:all:2.0').invoke }.
      to change { File.exist?(File.join(repositories.local, 'com/example/library/2.0/library-2.0-all.jar')) }.to(true)
  end

  it 'should deal well with repositories URL that lack the last slash' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist/base'
    uri = nil
    expect(URI).to receive(:download).twice { |_uri, args| uri = _uri }
    artifact('group:id:jar:1.0').invoke
    expect(uri.to_s).to eql('http://buildr.apache.org/repository/noexist/base/group/id/1.0/id-1.0.pom')
  end

  it 'should deal well with repositories URL that have the last slash' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist/base/'
    uri = nil
    expect(URI).to receive(:download).twice { |_uri, args| uri = _uri }
    artifact('group:id:jar:1.0').invoke
    expect(uri.to_s).to eql('http://buildr.apache.org/repository/noexist/base/group/id/1.0/id-1.0.pom')
  end

  it 'should resolve m2-style deployed snapshots' do
    metadata = <<-XML
    <?xml version='1.0' encoding='UTF-8'?>
    <metadata>
      <groupId>com.example</groupId>
      <artifactId>library</artifactId>
      <version>2.1-SNAPSHOT</version>
      <versioning>
        <snapshot>
          <timestamp>20071012.190008</timestamp>
          <buildNumber>8</buildNumber>
        </snapshot>
        <lastUpdated>20071012190008</lastUpdated>
      </versioning>
    </metadata>
    XML
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    #expect(URI).to receive(:download).twice.with(uri(/2.1-SNAPSHOT\/library-2.1-SNAPSHOT.(jar|pom)$/), anything()) { fail URI::NotFoundError }
    expect(URI).to receive(:download).twice.with(uri(/2.1-SNAPSHOT\/maven-metadata.xml$/), anything()) { |uri, target, options| target.write(metadata) }
    expect(URI).to receive(:download).twice.with(uri(/2.1-SNAPSHOT\/library-2.1-20071012.190008-8.(jar|pom)$/), /2.1-SNAPSHOT\/library-2.1-SNAPSHOT.(jar|pom).(\d){1,}$/) { |uri, target, options| write target }
    expect { artifact('com.example:library:jar:2.1-SNAPSHOT').invoke }.
      to change { File.exist?(File.join(repositories.local, 'com/example/library/2.1-SNAPSHOT/library-2.1-SNAPSHOT.jar')) }.to(true)
  end

  it 'should resolve m2-style deployed snapshots with classifiers' do
    metadata = <<-XML
    <?xml version='1.0' encoding='UTF-8'?>
    <metadata>
      <groupId>com.example</groupId>
      <artifactId>library</artifactId>
      <version>2.1-SNAPSHOT</version>
      <versioning>
        <snapshot>
          <timestamp>20071012.190008</timestamp>
          <buildNumber>8</buildNumber>
        </snapshot>
        <lastUpdated>20071012190008</lastUpdated>
      </versioning>
    </metadata>
    XML
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).once.with(uri(/2.1-SNAPSHOT\/library-2.1-20071012.190008-8-classifier.jar$/), anything()) { |uri, target, options| write target }
    expect(URI).to receive(:download).once.with(uri(/2.1-SNAPSHOT\/maven-metadata.xml$/), anything()) { |uri, target, options| target.write(metadata) }
    puts repositories.local
    expect { artifact('com.example:library:jar:classifier:2.1-SNAPSHOT').invoke}.
      to change {File.exists?(File.join(repositories.local, 'com/example/library/2.1-SNAPSHOT/library-2.1-SNAPSHOT-classifier.jar')) }.to(true)
  end

  it 'should fail resolving m2-style deployed snapshots if a timestamp is missing' do
    metadata = <<-XML
    <?xml version='1.0' encoding='UTF-8'?>
    <metadata>
      <groupId>com.example</groupId>
      <artifactId>library</artifactId>
      <version>2.1-SNAPSHOT</version>
      <versioning>
        <snapshot>
          <buildNumber>8</buildNumber>
        </snapshot>
        <lastUpdated>20071012190008</lastUpdated>
      </versioning>
    </metadata>
    XML
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).once.with(uri(/2.1-SNAPSHOT\/maven-metadata.xml$/), anything()) { |uri, target, options| target.write(metadata) }
    expect(URI).to receive(:download).once.with(uri(/2.1-SNAPSHOT\/library-2.1-SNAPSHOT.(jar|pom)$/), anything()) { fail URI::NotFoundError }
    expect {
      expect { artifact('com.example:library:jar:2.1-SNAPSHOT').invoke }.to raise_error(RuntimeError, /Failed to download/)
    }.to show_error "No timestamp provided for the snapshot com.example:library:jar:2.1-SNAPSHOT"
    expect(File.exist?(File.join(repositories.local, 'com/example/library/2.1-SNAPSHOT/library-2.1-SNAPSHOT.jar'))).to be_falsey
  end

  it 'should fail resolving m2-style deployed snapshots if a build number is missing' do
    metadata = <<-XML
    <?xml version='1.0' encoding='UTF-8'?>
    <metadata>
      <groupId>com.example</groupId>
      <artifactId>library</artifactId>
      <version>2.1-SNAPSHOT</version>
      <versioning>
        <snapshot>
          <timestamp>20071012.190008</timestamp>
        </snapshot>
        <lastUpdated>20071012190008</lastUpdated>
      </versioning>
    </metadata>
    XML
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).once.with(uri(/2.1-SNAPSHOT\/maven-metadata.xml$/), anything()) { |uri, target, options| target.write(metadata) }
    expect(URI).to receive(:download).once.with(uri(/2.1-SNAPSHOT\/library-2.1-SNAPSHOT.(jar|pom)$/), anything()) { fail URI::NotFoundError }
    expect {
      expect { artifact('com.example:library:jar:2.1-SNAPSHOT').invoke }.to raise_error(RuntimeError, /Failed to download/)
    }.to show_error "No build number provided for the snapshot com.example:library:jar:2.1-SNAPSHOT"
    expect(File.exist?(File.join(repositories.local, 'com/example/library/2.1-SNAPSHOT/library-2.1-SNAPSHOT.jar'))).to be_falsey
  end

  it 'should handle missing maven metadata by reporting the artifact unavailable' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).with(uri(/2.1-SNAPSHOT\/maven-metadata.xml$/), anything()) { fail URI::NotFoundError }
    expect(URI).to receive(:download).with(uri(/2.1-SNAPSHOT\/library-2.1-SNAPSHOT.jar$/), anything()) { fail URI::NotFoundError }
    expect { artifact('com.example:library:jar:2.1-SNAPSHOT').invoke }.to raise_error(RuntimeError, /Failed to download/)
    expect(File.exist?(File.join(repositories.local, 'com/example/library/2.1-SNAPSHOT/library-2.1-SNAPSHOT.jar'))).to be_falsey
  end

  it 'should handle missing m2 snapshots by reporting the artifact unavailable' do
    metadata = <<-XML
    <?xml version='1.0' encoding='UTF-8'?>
    <metadata>
      <groupId>com.example</groupId>
      <artifactId>library</artifactId>
      <version>2.1-SNAPSHOT</version>
      <versioning>
        <snapshot>
          <timestamp>20071012.190008</timestamp>
          <buildNumber>8</buildNumber>
        </snapshot>
        <lastUpdated>20071012190008</lastUpdated>
      </versioning>
    </metadata>
    XML
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).with(uri(/2.1-SNAPSHOT\/maven-metadata.xml$/), duck_type(:write)) { |uri, target, options| target.write(metadata) }
    expect(URI).to receive(:download).with(uri(/2.1-SNAPSHOT\/library-2.1-SNAPSHOT.jar$/), anything()) { fail URI::NotFoundError }
    expect(URI).to receive(:download).with(uri(/2.1-SNAPSHOT\/library-2.1-20071012.190008-8.jar$/), anything()) { fail URI::NotFoundError }
    expect { artifact('com.example:library:jar:2.1-SNAPSHOT').invoke }.to raise_error(RuntimeError, /Failed to download/)
    expect(File.exist?(File.join(repositories.local, 'com/example/library/2.1-SNAPSHOT/library-2.1-SNAPSHOT.jar'))).to be_falsey
  end

  it 'should load with all repositories specified in settings file' do
    write 'home/.buildr/settings.yaml', <<-YAML
    repositories:
      remote:
      - http://buildr.apache.org/repository/noexist
      - http://example.org
    YAML
    expect(repositories.remote).to include('http://buildr.apache.org/repository/noexist', 'http://example.org')
  end

  it 'should load with all repositories specified in build.yaml file' do
    write 'build.yaml', <<-YAML
    repositories:
      remote:
      - http://buildr.apache.org/repository/noexist
      - http://example.org
    YAML
    expect(repositories.remote).to include('http://buildr.apache.org/repository/noexist', 'http://example.org')
  end

  it 'should load with all repositories specified in settings and build.yaml files' do
    write 'home/.buildr/settings.yaml', <<-YAML
    repositories:
      remote:
      - http://buildr.apache.org/repository/noexist
    YAML
    write 'build.yaml', <<-YAML
    repositories:
      remote:
      - http://example.org
    YAML
    expect(repositories.remote).to include('http://buildr.apache.org/repository/noexist', 'http://example.org')
  end
end


describe Repositories, 'release_to' do
  it 'should accept URL as first argument' do
    repositories.release_to = 'http://buildr.apache.org/repository/noexist'
    expect(repositories.release_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist' })
  end

  it 'should accept hash with options' do
    repositories.release_to = { :url=>'http://buildr.apache.org/repository/noexist', :username=>'john' }
    expect(repositories.release_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist', :username=>'john' })
  end

  it 'should allow the hash to be manipulated' do
    repositories.release_to = 'http://buildr.apache.org/repository/noexist'
    expect(repositories.release_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist' })
    repositories.release_to[:username] = 'john'
    expect(repositories.release_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist', :username=>'john' })
  end

  it 'should load URL from settings file' do
    write 'home/.buildr/settings.yaml', <<-YAML
    repositories:
      release_to: http://john:secret@buildr.apache.org/repository/noexist
    YAML
    expect(repositories.release_to).to eq({ :url=>'http://john:secret@buildr.apache.org/repository/noexist' })
  end

  it 'should load URL from build settings file' do
    write 'build.yaml', <<-YAML
    repositories:
      release_to: http://john:secret@buildr.apache.org/repository/noexist
    YAML
    expect(repositories.release_to).to eq({ :url=>'http://john:secret@buildr.apache.org/repository/noexist' })
  end

  it 'should load URL, username and password from settings file' do
    write 'home/.buildr/settings.yaml', <<-YAML
    repositories:
      release_to:
        url: http://buildr.apache.org/repository/noexist
        username: john
        password: secret
    YAML
    expect(repositories.release_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist', :username=>'john', :password=>'secret' })
  end
end

describe Repositories, 'snapshot_to' do
  it 'should accept URL as first argument' do
    repositories.snapshot_to = 'http://buildr.apache.org/repository/noexist'
    expect(repositories.snapshot_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist' })
  end

  it 'should accept hash with options' do
    repositories.snapshot_to = { :url=>'http://buildr.apache.org/repository/noexist', :username=>'john' }
    expect(repositories.snapshot_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist', :username=>'john' })
  end

  it 'should allow the hash to be manipulated' do
    repositories.snapshot_to = 'http://buildr.apache.org/repository/noexist'
    expect(repositories.snapshot_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist' })
    repositories.snapshot_to[:username] = 'john'
    expect(repositories.snapshot_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist', :username=>'john' })
  end

  it 'should load URL from settings file' do
    write 'home/.buildr/settings.yaml', <<-YAML
    repositories:
      snapshot_to: http://john:secret@buildr.apache.org/repository/noexist
    YAML
    expect(repositories.snapshot_to).to eq({ :url=>'http://john:secret@buildr.apache.org/repository/noexist' })
  end

  it 'should load URL from build settings file' do
    write 'build.yaml', <<-YAML
    repositories:
      snapshot_to: http://john:secret@buildr.apache.org/repository/noexist
    YAML
    expect(repositories.snapshot_to).to eq({ :url=>'http://john:secret@buildr.apache.org/repository/noexist' })
  end

  it 'should load URL, username and password from settings file' do
    write 'home/.buildr/settings.yaml', <<-YAML
    repositories:
      snapshot_to:
        url: http://buildr.apache.org/repository/noexist
        username: john
        password: secret
    YAML
    expect(repositories.snapshot_to).to eq({ :url=>'http://buildr.apache.org/repository/noexist', :username=>'john', :password=>'secret' })
  end
end

describe Buildr, '#artifact' do
  before do
    @spec = { :group=>'com.example', :id=>'library', :type=>'jar', :version=>'2.0' }
    @snapshot_spec = 'group:id:jar:1.0-SNAPSHOT'
    write @file = 'testartifact.jar'
  end

  it 'should accept hash specification' do
    expect(artifact(:group=>'com.example', :id=>'library', :type=>'jar', :version=>'2.0')).to respond_to(:invoke)
  end

  it 'should reject partial hash specifier' do
    expect { artifact(@spec.merge(:group=>nil)) }.to raise_error /Missing group identifier/
    expect { artifact(@spec.merge(:id=>nil)) }.to raise_error /Missing artifact identifier/
    expect { artifact(@spec.merge(:version=>nil)) }.to raise_error /Missing version/
  end

  it 'should complain about invalid key' do
    expect { artifact(@spec.merge(:error=>true)) }.to raise_error(ArgumentError, /no such option/i)
  end

  it 'should use JAR type by default' do
    expect(artifact(@spec.merge(:type=>nil))).to respond_to(:invoke)
  end

  it 'should accept string specification' do
    expect(artifact('com.example:library:jar:2.0')).to respond_to(:invoke)
  end

  it 'should reject partial string specifier' do
    artifact('com.example:library::2.0')
    expect { artifact('com.example:library:jar') }.to raise_error /Missing version/
    expect { artifact('com.example:library:jar:') }.to raise_error /Missing version/
    expect { artifact('com.example:library::2.0') }.not_to raise_error 
    expect { artifact('com.example::jar:2.0') }.to raise_error /Missing artifact identifier/
    expect { artifact(':library:jar:2.0') }.to raise_error /Missing group identifier/
  end

  it 'should create a task naming the artifact in the local repository' do
    file = File.join(repositories.local, 'com', 'example', 'library', '2.0', 'library-2.0.jar')
    expect(Rake::Task.task_defined?(file)).to be_falsey
    expect(artifact('com.example:library:jar:2.0').name).to eql(file)
  end

  it 'should use from method to install artifact from existing file' do
    write 'test.jar'
    artifact = artifact('group:id:jar:1.0').from('test.jar')
    expect { artifact.invoke }.to change { File.exist?(artifact.to_s) }.to(true)
  end

  it 'should use from method to install artifact from a file task' do
    test_jar = file('test.jar')
    test_jar.enhance do
      #nothing...
    end
    write 'test.jar'
    artifact = artifact('group:id:jar:1.0').from(test_jar)
    expect { artifact.invoke }.to change { File.exist?(artifact.to_s) }.to(true)
  end

  it 'should invoke the artifact associated file task if the file doesnt exist' do
    test_jar = file('test.jar')
    called = false
    test_jar.enhance do
      write 'test.jar'
      called = true
    end
    artifact = artifact('group:id:jar:1.0').from(test_jar)
    artifact.invoke
    unless called
      raise "The file task was not called."
    end
  end

  it 'should not invoke the artifact associated file task if the file already exists' do
    test_jar = file('test.jar')
    test_jar.enhance do
      raise 'the test.jar file is created again!'
    end
    write 'test.jar'
    artifact = artifact('group:id:jar:1.0').from(test_jar)
    artifact.invoke
  end

  it 'should reference artifacts defined on build.yaml by using ruby symbols' do
    write 'build.yaml', <<-YAML
      artifacts:
        j2ee: geronimo-spec:geronimo-spec-j2ee:jar:1.4-rc4
    YAML
    Buildr.application.send(:load_artifact_ns)
    expect(artifact(:j2ee).to_s.pathmap('%f')).to eq('geronimo-spec-j2ee-1.4-rc4.jar')
  end

  it 'should try to download snapshot artifact' do
    run_with_repo
    snapshot = artifact(@snapshot_spec)

    expect(URI).to receive(:download).at_least(:twice) { |uri, target, options| write target }
    expect(FileUtils).to receive(:mv).at_least(:twice)
    snapshot.invoke
  end

  it 'should not try to update snapshot in offline mode if it exists' do
    run_with_repo
    snapshot = artifact(@snapshot_spec)
    write snapshot.to_s
    Buildr.application.options.work_offline = true
    expect(URI).to receive(:download).exactly(0).times
    snapshot.invoke
  end

  it 'should download snapshot even in offline mode if it doesn''t exist' do
    run_with_repo
    snapshot = artifact(@snapshot_spec)
    Buildr.application.options.work_offline = true
    expect(URI).to receive(:download).exactly(2).times
    snapshot.invoke
  end

  it 'should update snapshots if --update-snapshots' do
    run_with_repo
    snapshot = artifact(@snapshot_spec)
    write snapshot.to_s
    Buildr.application.options.update_snapshots = true

    expect(URI).to receive(:download).at_least(:twice) { |uri, target, options| write target }
    expect(FileUtils).to receive(:mv).at_least(:twice)
    snapshot.invoke
  end

  it 'should update snapshot if it''s older than 24 hours' do
    run_with_repo
    snapshot = artifact(@snapshot_spec)
    write snapshot.to_s
    time = Time.at((Time.now - (60 * 60 * 24) - 10 ).to_i)
    File.utime(time, time, snapshot.to_s)
    expect(URI).to receive(:download).at_least(:once) { |uri, target, options| write target }
    snapshot.invoke
  end

  def run_with_repo
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
  end

end


describe Buildr, '#artifacts' do
  it 'should return a list of artifacts from all its arguments' do
    specs = [ 'saxon:saxon:jar:8.4', 'saxon:saxon-dom:jar:8.4', 'saxon:saxon-xpath:jar:8.4' ]
    expect(artifacts(*specs)).to eql(specs.map { |spec| artifact(spec) })
  end

  it 'should accept nested arrays' do
    specs = [ 'saxon:saxon:jar:8.4', 'saxon:saxon-dom:jar:8.4', 'saxon:saxon-xpath:jar:8.4' ]
    expect(artifacts([[specs[0]]], [[specs[1]], specs[2]])).to eql(specs.map { |spec| artifact(spec) })
  end

  it 'should accept struct' do
    specs = struct(:main=>'saxon:saxon:jar:8.4', :dom=>'saxon:saxon-dom:jar:8.4', :xpath=>'saxon:saxon-xpath:jar:8.4')
    expect(artifacts(specs)).to eql(specs.values.map { |spec| artifact(spec) })
  end

  it 'should ignore duplicates' do
    expect(artifacts('saxon:saxon:jar:8.4', 'saxon:saxon:jar:8.4').size).to be(1)
  end

  it 'should accept and return existing tasks' do
    expect(artifacts(task('foo'), task('bar'))).to eql([task('foo'), task('bar')])
  end

  it 'should accept filenames and expand them' do
    expect(artifacts('test').map(&:to_s)).to eql([File.expand_path('test')])
  end

  it 'should accept filenames and return filenames' do
    expect(artifacts('c:test').first).to be_kind_of(String)
  end

  it 'should accept any object responding to :to_spec' do
    obj = Object.new
    class << obj
      def to_spec; "org.example:artifact:jar:1.1"; end
    end
    expect(artifacts(obj).size).to be(1)
  end

  it 'should accept project and return all its packaging tasks' do
    define 'foobar', :group=>'group', :version=>'1.0' do
      package :jar, :id=>'code'
      package :war, :id=>'webapp'
    end
    foobar = project('foobar')
    expect(artifacts(foobar)).to eql([
      task(foobar.path_to('target/code-1.0.jar')),
      task(foobar.path_to('target/webapp-1.0.war'))
    ])
  end

  it 'should complain about an invalid specification' do
    expect { artifacts(5) }.to raise_error /Invalid artifact specification/
    expect { artifacts('group:no:version:') }.to raise_error /Missing version/
  end
end


describe Buildr, '#group' do
  it 'should accept list of artifact identifiers' do
    list = group('saxon', 'saxon-dom', 'saxon-xpath', :under=>'saxon', :version=>'8.4')
    expect(list).to include(artifact('saxon:saxon:jar:8.4'))
    expect(list).to include(artifact('saxon:saxon-dom:jar:8.4'))
    expect(list).to include(artifact('saxon:saxon-xpath:jar:8.4'))
    expect(list.size).to be(3)
  end

  it 'should accept array with artifact identifiers' do
    list = group(%w{saxon saxon-dom saxon-xpath}, :under=>'saxon', :version=>'8.4')
    expect(list).to include(artifact('saxon:saxon:jar:8.4'))
    expect(list).to include(artifact('saxon:saxon-dom:jar:8.4'))
    expect(list).to include(artifact('saxon:saxon-xpath:jar:8.4'))
    expect(list.size).to be(3)
  end

  it 'should accept a type' do
    list = group('struts-bean', 'struts-html', :under=>'struts', :type=>'tld', :version=>'1.1')
    expect(list).to include(artifact('struts:struts-bean:tld:1.1'))
    expect(list).to include(artifact('struts:struts-html:tld:1.1'))
    expect(list.size).to be(2)
  end

  it 'should accept a classifier' do
    list = group('camel-core', :under=>'org.apache.camel', :version=>'2.2.0', :classifier=>'spring3')
    expect(list).to include(artifact('org.apache.camel:camel-core:jar:spring3:2.2.0'))
    expect(list.size).to be(1)
  end

end

describe Buildr, '#install' do
  before do
    @spec = 'group:id:jar:1.0'
    write @file = 'test.jar'
    @snapshot_spec = 'group:id:jar:1.0-SNAPSHOT'
  end

  it 'should return the install task' do
    expect(install).to be(task('install'))
  end

  it 'should accept artifacts to install' do
    install artifact(@spec)
    expect { install @file }.to raise_error(ArgumentError)
  end

  it 'should install artifact when install task is run' do
    write @file
    install artifact(@spec).from(@file)
    expect { install.invoke }.to change { File.exist?(artifact(@spec).to_s) }.to(true)
  end

  it 'should re-install artifact when "from" is newer' do
    install artifact(@spec).from(@file)
    write artifact(@spec).to_s # install a version of the artifact
    old_mtime = File.mtime(artifact(@spec).to_s)
    sleep 1; write @file       # make sure the "from" file has newer modification time
    expect { install.invoke }.to change { modified?(old_mtime, @spec) }.to(true)
  end

  it 'should re-install snapshot artifact when "from" is newer' do
    install artifact(@snapshot_spec).from(@file)
    write artifact(@snapshot_spec).to_s # install a version of the artifact
    old_mtime = File.mtime(artifact(@snapshot_spec).to_s)
    sleep 1; write @file       # make sure the "from" file has newer modification time
    expect { install.invoke }.to change { modified?(old_mtime, @snapshot_spec) }.to(true)
  end

  it 'should download snapshot to temporary location' do
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    snapshot = artifact(@snapshot_spec)
    same_time = Time.new
    download_file = "#{Dir.tmpdir}/#{File.basename(snapshot.name)}#{same_time.to_i}"

    expect(Time).to receive(:new).twice.and_return(same_time)
    expect(URI).to receive(:download).at_least(:twice) { |uri, target, options| write target }
    expect(FileUtils).to receive(:mv).at_least(:twice)
    snapshot.invoke
  end

  it 'should install POM alongside artifact (if artifact has no classifier)' do
    pom = artifact(@spec).pom
    write @file
    install artifact(@spec).from(@file)
    expect { install.invoke }.to change { File.exist?(repositories.locate(pom)) }.to(true)
  end

  it 'should not install POM alongside artifact if artifact has classifier' do
    @spec = 'group:id:jar:all:1.0'
    pom = artifact(@spec).pom
    write @file
    p method(:install)
    install artifact(@spec).from(@file)
    expect { install.invoke }.not_to change { File.exist?(repositories.locate(pom)) }
  end

  it 'should reinstall POM alongside artifact' do
    pom = artifact(@spec).pom
    write @file
    write repositories.locate(pom)
    sleep 1

    install artifact(@spec).from(@file)
    expect { install.invoke }.to change { File.mtime(repositories.locate(pom)) }
  end
end


describe Buildr, '#upload' do
  before do
    @spec = 'group:id:jar:1.0'
    write @file = 'test.jar'
    repositories.release_to = 'sftp://buildr.apache.org/repository/noexist/base'
  end

  it 'should return the upload task' do
    expect(upload).to be(task('upload'))
  end

  it 'should accept artifacts to upload' do
    upload artifact(@spec)
    expect { upload @file }.to raise_error(ArgumentError)
  end

  it 'should upload artifact when upload task is run' do
    write @file
    upload artifact(@spec).from(@file)
    expect(URI).to receive(:upload).once.
      with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/group/id/1.0/id-1.0.jar'), artifact(@spec).to_s, anything)
    expect(URI).to receive(:upload).once.
      with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/group/id/1.0/id-1.0.pom'), artifact(@spec).pom.to_s, anything)
    upload.invoke
  end
end


describe ActsAsArtifact, '#upload' do
  it 'should be used to upload artifact' do
    artifact = artifact('com.example:library:jar:2.0')
    # Prevent artifact from downloading anything.
    write repositories.locate(artifact)
    write repositories.locate(artifact.pom)
    expect(URI).to receive(:upload).once.
      with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/com/example/library/2.0/library-2.0.pom'), artifact.pom.to_s, anything)
    expect(URI).to receive(:upload).once.
      with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/com/example/library/2.0/library-2.0.jar'), artifact.to_s, anything)
    verbose(false) { artifact.upload(:url=>'sftp://buildr.apache.org/repository/noexist/base') }
  end

  it 'should support artifact classifier and should not upload pom if artifact has classifier' do
    artifact = artifact('com.example:library:jar:all:2.0')
    # Prevent artifact from downloading anything.
    write repositories.locate(artifact)
    expect(URI).to receive(:upload).exactly(:once).
      with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/com/example/library/2.0/library-2.0-all.jar'), artifact.to_s, anything)
    verbose(false) { artifact.upload(:url=>'sftp://buildr.apache.org/repository/noexist/base') }
  end

  it 'should complain without any repository configuration' do
    artifact = artifact('com.example:library:jar:2.0')
    # Prevent artifact from downloading anything.
    write repositories.locate(artifact)
    write repositories.locate(artifact.pom)
    expect { artifact.upload }.to raise_error(Exception, /where to upload/)
  end

  it 'should accept repositories.release_to setting' do
    artifact = artifact('com.example:library:jar:2.0')
    # Prevent artifact from downloading anything.
    write repositories.locate(artifact)
    write repositories.locate(artifact.pom)
    expect(URI).to receive(:upload).at_least(:once)
    repositories.release_to = 'sftp://buildr.apache.org/repository/noexist/base'
    artifact.upload
    expect { artifact.upload }.not_to raise_error
  end

  it 'should use repositories.release_to setting even for snapshots when snapshot_to is not set' do
    artifact = artifact('com.example:library:jar:2.0-SNAPSHOT')
    # Prevent artifact from downloading anything.
    write repositories.locate(artifact)
    write repositories.locate(artifact.pom)
    expect(URI).to receive(:upload).once.
      with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/com/example/library/2.0-SNAPSHOT/library-2.0-SNAPSHOT.pom'), artifact.pom.to_s, anything)
    expect(URI).to receive(:upload).once.
      with(URI.parse('sftp://buildr.apache.org/repository/noexist/base/com/example/library/2.0-SNAPSHOT/library-2.0-SNAPSHOT.jar'), artifact.to_s, anything)
    repositories.release_to = 'sftp://buildr.apache.org/repository/noexist/base'
    artifact.upload
    expect { artifact.upload }.not_to raise_error
  end

  it 'should use repositories.snapshot_to setting when snapshot_to is set' do
    artifact = artifact('com.example:library:jar:2.0-SNAPSHOT')
    # Prevent artifact from downloading anything.
    write repositories.locate(artifact)
    write repositories.locate(artifact.pom)
    expect(URI).to receive(:upload).once.
      with(URI.parse('sftp://buildr.apache.org/repository/noexist/snapshot/com/example/library/2.0-SNAPSHOT/library-2.0-SNAPSHOT.pom'), artifact.pom.to_s, anything)
    expect(URI).to receive(:upload).once.
      with(URI.parse('sftp://buildr.apache.org/repository/noexist/snapshot/com/example/library/2.0-SNAPSHOT/library-2.0-SNAPSHOT.jar'), artifact.to_s, anything)
    repositories.release_to = 'sftp://buildr.apache.org/repository/noexist/base'
    repositories.snapshot_to = 'sftp://buildr.apache.org/repository/noexist/snapshot'
    artifact.upload
    expect { artifact.upload }.not_to raise_error
  end

  it 'should complain when only a snapshot repo is set but the artifact is not a snapshot' do
    artifact = artifact('com.example:library:jar:2.0')
    # Prevent artifact from downloading anything.
    write repositories.locate(artifact)
    write repositories.locate(artifact.pom)
    repositories.snapshot_to = 'sftp://buildr.apache.org/repository/noexist/snapshot'
    expect { artifact.upload }.to raise_error(Exception, /where to upload/)
  end


end


describe Rake::Task, ' artifacts' do
  before do
    Buildr.repositories.instance_eval do
      @local = @remote = @release_to = nil
    end
  end

  it 'should download all specified artifacts' do
    artifact 'group:id:jar:1.0'
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    expect(URI).to receive(:download).twice { |uri, target, options| write target }
    task('artifacts').invoke
  end

  it 'should fail if failed to download an artifact' do
    artifact 'group:id:jar:1.0'
    expect { task('artifacts').invoke }.to raise_error(RuntimeError, /No remote repositories/)
  end

  it 'should succeed if artifact already exists' do
    write repositories.locate(artifact('group:id:jar:1.0'))
    suppress_stdout do
      expect { task('artifacts').invoke }.not_to raise_error
    end
  end
end


describe Rake::Task, ' artifacts:sources' do

  before do
    Buildr.repositories.instance_eval do
      @local = @remote = @release_to = nil
    end
    task('artifacts:sources').clear
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
  end

  it 'should download sources for all specified artifacts' do
    artifact 'group:id:jar:1.0'
    allow(URI).to receive(:download) { |uri, target| write target }
    expect { task('artifacts:sources').invoke }.to change { File.exist?('home/.m2/repository/group/id/1.0/id-1.0-sources.jar') }.to(true)
  end

  it "should not try to download sources for the project's artifacts" do
    define('foo', :version=>'1.0') { package(:jar) }
    expect(URI).not_to receive(:download)
    task('artifacts:sources').invoke
  end

  describe 'when the source artifact does not exist' do

    before do
      artifact 'group:id:jar:1.0'
      expect(URI).to receive(:download).and_raise(URI::NotFoundError)
    end

    it 'should not fail' do
      expect { task('artifacts:sources').invoke }.not_to raise_error
    end

    it 'should inform the user' do
      expect { task('artifacts:sources').invoke }.to show_info('Failed to download group:id:jar:sources:1.0. Skipping it.')
    end
  end
end

describe Rake::Task, ' artifacts:javadoc' do

  before do
    Buildr.repositories.instance_eval do
      @local = @remote = @release_to = nil
    end
    task('artifacts:javadoc').clear
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
  end

  it 'should download javadoc for all specified artifacts' do
    artifact 'group:id:jar:1.0'
    expect(URI).to receive(:download) { |uri, target| write target }
    expect { task('artifacts:javadoc').invoke }.to change { File.exist?('home/.m2/repository/group/id/1.0/id-1.0-javadoc.jar') }.to(true)
  end

  it "should not try to download javadoc for the project's artifacts" do
    define('foo', :version=>'1.0') { package(:jar) }
    expect(URI).not_to receive(:download)
    task('artifacts:javadoc').invoke
  end

  describe 'when the javadoc artifact does not exist' do

    before do
      artifact 'group:id:jar:1.0'
      expect(URI).to receive(:download).and_raise(URI::NotFoundError)
    end

    it 'should not fail' do
      expect { task('artifacts:javadoc').invoke }.not_to raise_error
    end

    it 'should inform the user' do
      expect { task('artifacts:javadoc').invoke }.to show_info('Failed to download group:id:jar:javadoc:1.0. Skipping it.')
    end
  end
end

describe Buildr, '#transitive' do
  before do
    repositories.remote = 'http://buildr.apache.org/repository/noexist'
    @simple = [ 'saxon:saxon:jar:8.4', 'saxon:saxon-dom:jar:8.4', 'saxon:saxon-xpath:jar:8.4' ]
    @simple.map { |spec| artifact(spec).pom }.each { |task| write task.name, task.pom_xml.call }
    @provided = @simple.first
    @complex = 'group:app:jar:1.0'
    write artifact(@complex).pom.to_s, <<-XML
<project>
  <artifactId>app</artifactId>
  <groupId>group</groupId>
  <dependencies>
    <dependency>
      <artifactId>saxon</artifactId>
      <groupId>saxon</groupId>
      <version>8.4</version>
      <scope>provided</scope>
    </dependency>
    <dependency>
      <artifactId>saxon-dom</artifactId>
      <groupId>saxon</groupId>
      <version>8.4</version>
      <scope>runtime</scope>
    </dependency>
    <dependency>
      <artifactId>saxon-xpath</artifactId>
      <groupId>saxon</groupId>
      <version>8.4</version>
    </dependency>
    <dependency>
      <artifactId>saxon-nosuch</artifactId>
      <groupId>saxon</groupId>
      <version>8.4</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <artifactId>jlib-optional</artifactId>
      <groupId>jlib</groupId>
      <version>1.4</version>
      <scope>runtime</scope>
      <optional>true</optional>
    </dependency>
  </dependencies>
</project>
XML
    @transitive = 'master:app:war:1.0'
    write artifact(@transitive).pom.to_s, <<-XML
<project>
  <artifactId>app</artifactId>
  <groupId>group</groupId>
  <dependencies>
    <dependency>
      <artifactId>app</artifactId>
      <groupId>group</groupId>
      <version>1.0</version>
    </dependency>
  </dependencies>
</project>
XML
  end

  it 'should return a list of artifacts from all its arguments' do
    specs = [ 'saxon:saxon:jar:8.4', 'saxon:saxon-dom:jar:8.4', 'saxon:saxon-xpath:jar:8.4' ]
    expect(transitive(*specs)).to eql(specs.map { |spec| artifact(spec) })
  end

  it 'should accept nested arrays' do
    specs = [ 'saxon:saxon:jar:8.4', 'saxon:saxon-dom:jar:8.4', 'saxon:saxon-xpath:jar:8.4' ]
    expect(transitive([[specs[0]]], [[specs[1]], specs[2]])).to eql(specs.map { |spec| artifact(spec) })
  end

  it 'should accept struct' do
    specs = struct(:main=>'saxon:saxon:jar:8.4', :dom=>'saxon:saxon-dom:jar:8.4', :xpath=>'saxon:saxon-xpath:jar:8.4')
    expect(transitive(specs)).to eql(specs.values.map { |spec| artifact(spec) })
  end

  it 'should ignore duplicates' do
    expect(transitive('saxon:saxon:jar:8.4', 'saxon:saxon:jar:8.4').size).to be(1)
  end

  it 'should accept and return existing tasks' do
    expect(transitive(task('foo'), task('bar'))).to eql([task('foo'), task('bar')])
  end

  it 'should accept filenames and expand them' do
    expect(transitive('test').map(&:to_s)).to eql([File.expand_path('test')])
  end

  it 'should accept filenames and return file task' do
    expect(transitive('c:test').first).to be_kind_of(Rake::FileTask)
  end

  it 'should accept project and return all its packaging tasks' do
    define 'foobar', :group=>'group', :version=>'1.0' do
      package :jar, :id=>'code'
      package :war, :id=>'webapp'
    end
    foobar = project('foobar')
    expect(transitive(foobar)).to eql([
      task(foobar.path_to('target/code-1.0.jar')),
      task(foobar.path_to('target/webapp-1.0.war'))
    ])
  end

  it 'should complain about an invalid specification' do
    expect { transitive(5) }.to raise_error /Invalid artifact specification/
    expect { transitive('group:no:version:') }.to raise_error /Missing version/
  end

  it 'should bring artifact and its dependencies' do
    expect(transitive(@complex)).to eql(artifacts(@complex, @simple - [@provided]))
  end

  it 'should bring dependencies of POM without artifact itself' do
    expect(transitive(@complex.sub(/jar/, 'pom'))).to eql(artifacts(@simple - [@provided]))
  end

  it 'should bring artifact and transitive depenencies' do
    expect(transitive(@transitive)).to eql(artifacts(@transitive, @complex, @simple - [@provided]))
  end

  it 'should filter dependencies based on :scopes argument' do
    specs = [@complex, 'saxon:saxon-dom:jar:8.4']
    expect(transitive(@complex, :scopes => [:runtime])).to eql(specs.map { |spec| artifact(spec) })
  end

  it 'should filter dependencies based on :optional argument' do
    specs = [@complex, 'saxon:saxon-dom:jar:8.4', 'jlib:jlib-optional:jar:1.4']
    expect(transitive(@complex, :scopes => [:runtime], :optional => true)).to eql(specs.map { |spec| artifact(spec) })
  end
end

def modified?(old_mtime, spec)
  File.exist?(artifact(spec).to_s) && old_mtime < File.mtime(artifact(spec).to_s)
end
