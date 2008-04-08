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


describe Buildr::Application do
  before :each do
    @app = Buildr.application
  end


  describe 'home_dir' do
    it 'should point to ~/.buildr' do
      @app.home_dir.should eql(File.expand_path('.buildr', ENV['HOME']))
    end

    it 'should point to existing directory' do
      File.directory?(@app.home_dir).should be_true
    end
  end


  describe 'settings' do
    it 'should be empty hash if no settings.yaml file' do
      @app.settings.should == {}
    end

    it 'should return loaded settings.yaml file' do
      write 'home/.buildr/settings.yaml', 'foo: bar'
      @app.settings.should == { 'foo'=>'bar' }
    end

    it 'should fail if settings.yaml file is not a hash' do
      write 'home/.buildr/settings.yaml', 'foo bar'
      lambda { @app.settings }.should raise_error(RuntimeError, /expecting.*settings.yaml/i)
    end

    it 'should be empty hash if settings.yaml file is empty' do
      write 'home/.buildr/settings.yaml'
      @app.settings.should == {}
    end
  end
  

  describe 'configuration' do
    it 'should be empty hash if no build.yaml file' do
      @app.configuration.should == {}
    end

    it 'should return loaded build.yaml file' do
      write 'build.yaml', 'foo: bar'
      @app.configuration.should == { 'foo'=>'bar' }
    end

    it 'should fail if build.yaml file is not a hash' do
      write 'build.yaml', 'foo bar'
      lambda { @app.configuration }.should raise_error(RuntimeError, /expecting.*build.yaml/i)
    end

    it 'should be empty hash if build.yaml file is empty' do
      write 'build.yaml'
      @app.configuration.should == {}
    end
  end


  describe 'profiles' do
    it 'should be empty hash if no profiles.yaml file' do
      @app.profiles.should == {}
    end

    it 'should return loaded profiles.yaml file' do
      write 'profiles.yaml', <<-YAML
        development:
          foo: bar
      YAML
      @app.profiles.should == { 'development'=> { 'foo'=>'bar' } }
    end

    it 'should fail if profiles.yaml file is not a hash' do
      write 'profiles.yaml', 'foo bar'
      lambda { @app.profiles }.should raise_error(RuntimeError, /expecting.*profiles.yaml/i)
    end

    it 'should be empty hash if profiles.yaml file is empty' do
      write 'profiles.yaml'
      @app.profiles.should == {}
    end
  end


  describe 'profile' do
    it 'should be empty hash if no profiles.yaml' do
      @app.profile.should == {}
    end

    it 'should be empty hash if no matching profile' do
      write 'profiles.yaml', <<-YAML
        test:
          foo: bar
      YAML
      @app.profile.should == {}
    end

    it 'should return profile matching environment name' do
      write 'profiles.yaml', <<-YAML
        development:
          foo: bar
        test:
          foo: baz
      YAML
      @app.profile.should == { 'foo'=>'bar' }
    end

  end


  describe 'gems' do

    def load_with_yaml
      write 'build.yaml', <<-YAML
        gems:
        - rspec
        - rake >= 0.8
      YAML
      @app.load_gems
    end

    it 'should return empty array if no gems specified' do
      @app.load_gems 
      @app.gems.should be_empty
    end

    it 'should return one entry for each gem specified in buildr.yaml' do
      load_with_yaml
      @app.gems.size.should be(2)
    end

    it 'should return a Gem::Specification for each installed gem' do
      load_with_yaml
      @app.gems.each { |gem| gem.should be_kind_of(Gem::Specification) }
    end

    it 'should parse Gem name correctly' do
      load_with_yaml
      @app.gems.map(&:name).should include('rake', 'rspec')
    end

    it 'should find installed version of Gem' do
      load_with_yaml
      @app.gems.each { |gem| gem.version.should eql(Gem.loaded_specs[gem.name].version) }
    end
  end


  describe 'load_gems' do
    before do
      @spec = Gem::Specification.new do |spec|
        spec.name = 'foo'
        spec.version = '1.2'
      end
    end

    it 'should do nothing if no gems specified' do
      lambda { @app.load_gems }.should_not raise_error
    end

    it 'should install nothing if specified gems already installed' do
      @app.should_receive(:listed_gems).and_return([Gem.loaded_specs['rspec']])
      Util.should_not_receive(:ruby)
      lambda { @app.load_gems }.should_not raise_error
    end

    it 'should fail if required gem not found in remote repository' do
      @app.should_receive(:listed_gems).and_return([Gem::Dependency.new('foo', '>=1.1')])
      Gem::SourceInfoCache.should_receive(:search).and_return([])
      lambda { @app.load_gems }.should raise_error(LoadError, /cannot be found/i)
    end

    it 'should fail if need to install gem and not running in interactive mode' do
      @app.should_receive(:listed_gems).and_return([Gem::Dependency.new('foo', '>=1.1')])
      Gem::SourceInfoCache.should_receive(:search).and_return([@spec])
      $stdout.should_receive(:isatty).and_return(false)
      lambda { @app.load_gems }.should raise_error(LoadError, /this build requires the gems/i)
    end

    it 'should ask permission before installing required gems' do
      @app.should_receive(:listed_gems).and_return([Gem::Dependency.new('foo', '>=1.1')])
      Gem::SourceInfoCache.should_receive(:search).and_return([@spec])
      $terminal.should_receive(:agree).with(/install/, true)
      lambda { @app.load_gems }.should raise_error
    end

    it 'should fail if permission not granted to install gem' do
      @app.should_receive(:listed_gems).and_return([Gem::Dependency.new('foo', '>=1.1')])
      Gem::SourceInfoCache.should_receive(:search).and_return([@spec])
      $terminal.should_receive(:agree).and_return(false)
      lambda { @app.load_gems }.should raise_error(LoadError, /cannot build without/i)
    end

    it 'should install gem if permission granted' do
      @app.should_receive(:listed_gems).and_return([Gem::Dependency.new('foo', '>=1.1')])
      Gem::SourceInfoCache.should_receive(:search).and_return([@spec])
      $terminal.should_receive(:agree).and_return(true)
      Util.should_receive(:ruby) do |*args|
        args.should include('install', 'foo', '-v', '1.2')
      end
      @app.should_receive(:gem).and_return(false)
      @app.load_gems
    end

    it 'should reload gem cache after installing required gems' do
      @app.should_receive(:listed_gems).and_return([Gem::Dependency.new('foo', '>=1.1')])
      Gem::SourceInfoCache.should_receive(:search).and_return([@spec])
      $terminal.should_receive(:agree).and_return(true)
      Util.should_receive(:ruby)
      Gem.source_index.should_receive(:load_gems_in).with(Gem::SourceIndex.installed_spec_directories)
      @app.should_receive(:gem).and_return(false)
      @app.load_gems
    end

    it 'should load previously installed gems' do
      @app.should_receive(:listed_gems).and_return([Gem.loaded_specs['rspec']])
      @app.should_receive(:gem).with('rspec', Gem.loaded_specs['rspec'].version.to_s)
      @app.load_gems
    end

    it 'should load newly installed gems' do
      @app.should_receive(:listed_gems).and_return([Gem::Dependency.new('foo', '>=1.1')])
      Gem::SourceInfoCache.should_receive(:search).and_return([@spec])
      $terminal.should_receive(:agree).and_return(true)
      Util.should_receive(:ruby)
      @app.should_receive(:gem).with('foo', @spec.version.to_s)
      @app.load_gems
    end

    it 'should default to >=0 version requirement if not specified' do
      write 'build.yaml', 'gems: foo'
      Gem::SourceInfoCache.should_receive(:search).with(Gem::Dependency.new('foo', '>=0')).and_return([])
      lambda { @app.load_gems }.should raise_error
    end

    it 'should parse exact version requirement' do
      write 'build.yaml', 'gems: foo 2.5'
      Gem::SourceInfoCache.should_receive(:search).with(Gem::Dependency.new('foo', '=2.5')).and_return([])
      lambda { @app.load_gems }.should raise_error
    end

    it 'should parse range version requirement' do
      write 'build.yaml', 'gems: foo ~>2.3'
      Gem::SourceInfoCache.should_receive(:search).with(Gem::Dependency.new('foo', '~>2.3')).and_return([])
      lambda { @app.load_gems }.should raise_error
    end

    it 'should parse multiple version requirements' do
      write 'build.yaml', 'gems: foo >=2.0 !=2.1'
      Gem::SourceInfoCache.should_receive(:search).with(Gem::Dependency.new('foo', ['>=2.0', '!=2.1'])).and_return([])
      lambda { @app.load_gems }.should raise_error
    end
  end

end


describe 'ENV' do

  describe 'BUILDR_ENV' do
    it 'should default to development' do
      ENV['BUILDR_ENV'].should eql('development')
    end
  end
end
