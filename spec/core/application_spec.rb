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


describe Buildr::Application do

  describe 'home_dir' do
    it 'should point to ~/.buildr' do
      expect(Buildr.application.home_dir).to eql(File.expand_path('.buildr', ENV['HOME']))
    end

    it 'should point to existing directory' do
      expect(File.directory?(Buildr.application.home_dir)).to be_truthy
    end
  end

  describe '#run' do
    it 'should execute *_load methods in order' do
      order = [:load_gems, :load_artifact_ns, :load_tasks, :raw_load_buildfile]
      order.each { |method| expect(Buildr.application).to receive(method).ordered }
      allow(Buildr.application).to receive(:exit) # With this, shows the correct error instead of SystemExit.
      Buildr.application.run
    end

    it 'should load imports after loading buildfile' do
      method = Buildr.application.method(:raw_load_buildfile)
      expect(Buildr.application).to receive(:raw_load_buildfile) do
        expect(Buildr.application).to receive(:load_imports)
        method.call
      end
      allow(Buildr.application).to receive(:exit) # With this, shows the correct error instead of SystemExit.
      Buildr.application.run
    end

    it 'should evaluate all projects after loading buildfile' do
      expect(Buildr.application).to receive(:load_imports) do
        expect(Buildr).to receive(:projects)
      end
      allow(Buildr.application).to receive(:exit) # With this, shows the correct error instead of SystemExit.
      Buildr.application.run
    end
  end

  describe 'environment' do
    it 'should return value of BUILDR_ENV' do
      ENV['BUILDR_ENV'] = 'qa'
      expect(Buildr.application.environment).to eql('qa')
    end

    it 'should default to development' do
      expect(Buildr.application.environment).to eql('development')
    end

    it 'should set environment name from -e argument' do
      ARGV.push('-e', 'test')
      Buildr.application.send(:handle_options)
      expect(Buildr.application.environment).to eql('test')
      expect(ENV['BUILDR_ENV']).to eql('test')
    end

    it 'should be echoed to user' do
      write 'buildfile'
      ENV['BUILDR_ENV'] = 'spec'
      Buildr.application.send(:handle_options)
      expect { Buildr.application.send :load_buildfile }.to show(%r{(in .*, spec)})
    end
  end

  describe 'options' do
    it "should have 'tasks' as the sole default rakelib" do
      Buildr.application.send(:handle_options)
      expect(Buildr.application.options.rakelib).to eq(['tasks'])
    end

    it 'should show the version when prompted with -V' do
      ARGV.push('-V')
      expect(test_exit(0) { Buildr.application.send(:handle_options) }).to show(/Buildr #{Buildr::VERSION}.*/)
    end

    it 'should show the version when prompted with --version' do
      ARGV.push('--version')
      expect(test_exit(0) { Buildr.application.send(:handle_options) }).to show(/Buildr #{Buildr::VERSION}.*/)
    end

    it 'should enable tracing with --trace' do
      ARGV.push('--trace')
      Buildr.application.send(:handle_options)
      expect(Buildr.application.options.trace).to eq(true)
    end

    it 'should enable tracing of [:foo, :bar] categories with --trace=foo,bar' do
      ARGV.push('--trace=foo,bar')
      Buildr.application.send(:handle_options)
      expect(Buildr.application.options.trace).to eq(true)
      expect(Buildr.application.options.trace_categories).to eq([:foo, :bar])
      expect(trace?(:foo)).to eq(true)
      expect(trace?(:not)).to eq(false)
    end

    it 'should enable tracing for all categories with --trace=all' do
      ARGV.push('--trace=all')
      Buildr.application.send(:handle_options)
      expect(Buildr.application.options.trace).to eq(true)
      expect(Buildr.application.options.trace_all).to eq(true)
      expect(trace?(:foo)).to eq(true)
    end

  end

  describe 'gems' do
    before do
      class << Buildr.application
        public :load_gems
      end
    end

    def load_with_yaml
      write 'build.yaml', <<-YAML
        gems:
        - rake
        - rspec ~> 2.9.0
      YAML
      expect(Buildr.application).to receive(:listed_gems).and_return([[Gem.loaded_specs['rspec'],Gem.loaded_specs['rake']],[]])
      Buildr.application.load_gems
    end

    it 'should return empty array if no gems specified' do
      Buildr.application.load_gems
      expect(Buildr.application.gems).to be_empty
    end

    it 'should return one entry for each gem specified in buildr.yaml' do
      load_with_yaml
      expect(Buildr.application.gems.size).to be(2)
    end

    it 'should return a Gem::Specification for each installed gem' do
      load_with_yaml
      Buildr.application.gems.each { |gem| expect(gem).to be_kind_of(Bundler::StubSpecification) }
    end

    it 'should parse Gem name correctly' do
      load_with_yaml
      expect(Buildr.application.gems.map(&:name)).to include('rspec', 'rake')
    end

    it 'should find installed version of Gem' do
      load_with_yaml
      Buildr.application.gems.each { |gem| expect(gem.version).to eql(Gem.loaded_specs[gem.name].version) }
    end
  end

  describe 'load_gems' do
    before do
      class << Buildr.application
        public :load_gems
      end
      @spec = Gem::Specification.new do |spec|
        spec.name = 'buildr-foo'
        spec.version = '1.2'
      end
      allow($stdout).to receive(:isatty).and_return(true)
    end

    it 'should do nothing if no gems specified' do
      expect { Buildr.application.load_gems }.not_to raise_error
    end

    it 'should install nothing if specified gems already installed' do
      expect(Buildr.application).to receive(:listed_gems).and_return([[Gem.loaded_specs['rspec']],[]])
      expect(Util).not_to receive(:ruby)
      expect { Buildr.application.load_gems }.not_to raise_error
    end

    it 'should fail if required gem not installed' do
      expect(Buildr.application).to receive(:listed_gems).and_return([[],[Gem::Dependency.new('buildr-foo', '>=1.1')]])
      expect { Buildr.application.load_gems }.to raise_error(LoadError, /cannot be found/i)
    end

    it 'should load previously installed gems' do
      expect(Gem.loaded_specs['rspec']).to receive(:activate)
      expect(Buildr.application).to receive(:listed_gems).and_return([[Gem.loaded_specs['rspec']],[]])
      #Buildr.application.should_receive(:gem).with('rspec', Gem.loaded_specs['rspec'].version.to_s)
      Buildr.application.load_gems
    end

    it 'should default to >=0 version requirement if not specified' do
      write 'build.yaml', 'gems: buildr-foo'
      should_attempt_to_load_dependency(Gem::Dependency.new('buildr-foo', '>= 0'))
    end

    it 'should parse exact version requirement' do
      write 'build.yaml', 'gems: buildr-foo 2.5'
      should_attempt_to_load_dependency(Gem::Dependency.new('buildr-foo', '=2.5'))
    end

    it 'should parse range version requirement' do
      write 'build.yaml', 'gems: buildr-foo ~>2.3'
      should_attempt_to_load_dependency(Gem::Dependency.new('buildr-foo', '~>2.3'))
    end

    it 'should parse multiple version requirements' do
      write 'build.yaml', 'gems: buildr-foo >=2.0 !=2.1'
      should_attempt_to_load_dependency(Gem::Dependency.new('buildr-foo', ['>=2.0', '!=2.1']))
    end

    def should_attempt_to_load_dependency(dep)
      missing_gems = Buildr.application.send(:listed_gems)[1]
      expect(missing_gems.size).to eql(1)
      missing_gems[0].eql?(dep)
    end
  end

  describe 'load_tasks' do
    before do
      class << Buildr.application
        public :load_tasks
      end
      @original_loaded_features = $LOADED_FEATURES.dup
      Buildr.application.options.rakelib = ["tasks"]
    end

    after do
      $taskfiles = nil
      ($LOADED_FEATURES - @original_loaded_features).each do |new_load|
        $LOADED_FEATURES.delete(new_load)
      end
    end

    def write_task(filename)
      write filename, <<-RUBY
        $taskfiles ||= []
        $taskfiles << __FILE__
      RUBY
    end

    def loaded_tasks
      @loaded ||= Buildr.application.load_tasks
      $taskfiles
    end

    it "should load {options.rakelib}/foo.rake" do
      write_task 'tasks/foo.rake'
      expect(loaded_tasks.size).to eq(1)
      expect(loaded_tasks.first).to match(%r{tasks/foo\.rake$})
    end

    it 'should load all *.rake files from the rakelib' do
      write_task 'tasks/bar.rake'
      write_task 'tasks/quux.rake'
      expect(loaded_tasks.size).to eq(2)
    end

    it 'should not load files which do not have the .rake extension' do
      write_task 'tasks/foo.rb'
      write_task 'tasks/bar.rake'
      expect(loaded_tasks.size).to eq(1)
      expect(loaded_tasks.first).to match(%r{tasks/bar\.rake$})
    end

    it 'should load files only from the directory specified in the rakelib option' do
      Buildr.application.options.rakelib = ['extensions']
      write_task 'extensions/amp.rake'
      write_task 'tasks/bar.rake'
      write_task 'extensions/foo.rake'
      expect(loaded_tasks.size).to eq(2)
      %w[amp foo].each do |filename|
        expect(loaded_tasks.select{|x| x =~ %r{extensions/#{filename}\.rake}}.size).to eq(1)
      end
    end

    it 'should load files from all the directories specified in the rakelib option' do
      Buildr.application.options.rakelib = ['ext', 'more', 'tasks']
      write_task 'ext/foo.rake'
      write_task 'tasks/bar.rake'
      write_task 'tasks/zeb.rake'
      write_task 'more/baz.rake'
      expect(loaded_tasks.size).to eq(4)
    end

    it 'should not load files from the rakelib more than once' do
      write_task 'tasks/new_one.rake'
      write_task 'tasks/already.rake'
      $LOADED_FEATURES << File.expand_path('tasks/already.rake')

      expect(loaded_tasks.size).to eq(1)
      expect(loaded_tasks.first).to match(%r{tasks/new_one\.rake$})
    end
  end

  describe 'exception handling' do

    it 'should exit when given a SystemExit exception' do
      test_exit(3) { Buildr.application.standard_exception_handling { raise SystemExit.new(3) } }
    end

    it 'should exit with status 1 when given an OptionParser::ParseError exception' do
      test_exit(1) { Buildr.application.standard_exception_handling { raise OptionParser::ParseError.new() } }
    end

    it 'should exit with status 1 when given any other type of exception exception' do
      test_exit(1) { Buildr.application.standard_exception_handling { raise Exception.new() } }
    end

    it 'should print the class name and the message when receiving an exception (except when the exception is named Exception)' do

      # Our fake $stderr for the exercise. We could start it with a matcher instead
      class FakeStdErr

        attr_accessor :messages

        def puts(*args)
          @messages ||= []
          @messages += args
        end

        alias :write :puts
      end

      # Save the old $stderr and make sure to restore it in the end.
      old_stderr = $stderr
      begin

        $stderr = FakeStdErr.new
        test_exit(1) {
          Buildr.application.send :standard_exception_handling do
            class MyOwnNicelyNamedException < Exception
            end
            raise MyOwnNicelyNamedException.new('My message')
          end
        }.call
        expect($stderr.messages.select {|msg| msg =~ /.*MyOwnNicelyNamedException : My message.*/}.size).to eq(1)
        $stderr.messages.clear
        test_exit(1) {
          Buildr.application.send :standard_exception_handling do
            raise Exception.new('My message')
          end
        }.call
        expect($stderr.messages.select {|msg| msg =~ /.*My message.*/ && !(msg =~ /Exception/)}.size).to eq(1)
      end
      $stderr = old_stderr
    end
  end

end


describe Buildr, 'settings' do

  describe 'user' do

    it 'should be empty hash if no settings.yaml file' do
      expect(Buildr.settings.user).to eq({})
    end

    it 'should return loaded settings.yaml file' do
      write 'home/.buildr/settings.yaml', 'foo: bar'
      expect(Buildr.settings.user).to eq({ 'foo'=>'bar' })
    end

    it 'should return loaded settings.yml file' do
      write 'home/.buildr/settings.yml', 'foo: bar'
      expect(Buildr.settings.user).to eq({ 'foo'=>'bar' })
    end

    it 'should fail if settings.yaml file is not a hash' do
      write 'home/.buildr/settings.yaml', 'foo bar'
      expect { Buildr.settings.user }.to raise_error(RuntimeError, /expecting.*settings.yaml/i)
    end

    it 'should be empty hash if settings.yaml file is empty' do
      write 'home/.buildr/settings.yaml'
      expect(Buildr.settings.user).to eq({})
    end
  end

  describe 'configuration' do
    it 'should be empty hash if no build.yaml file' do
      expect(Buildr.settings.build).to eq({})
    end

    it 'should return loaded build.yaml file' do
      write 'build.yaml', 'foo: bar'
      expect(Buildr.settings.build).to eq({ 'foo'=>'bar' })
    end

    it 'should return loaded build.yml file' do
      write 'build.yml', 'foo: bar'
      expect(Buildr.settings.build).to eq({ 'foo'=>'bar' })
    end

    it 'should fail if build.yaml file is not a hash' do
      write 'build.yaml', 'foo bar'
      expect { Buildr.settings.build }.to raise_error(RuntimeError, /expecting.*build.yaml/i)
    end

    it 'should be empty hash if build.yaml file is empty' do
      write 'build.yaml'
      expect(Buildr.settings.build).to eq({})
    end
  end

  describe 'profiles' do
    it 'should be empty hash if no profiles.yaml file' do
      expect(Buildr.settings.profiles).to eq({})
    end

    it 'should return loaded profiles.yaml file' do
      write 'profiles.yaml', <<-YAML
        development:
          foo: bar
      YAML
      expect(Buildr.settings.profiles).to eq({ 'development'=> { 'foo'=>'bar' } })
    end

    it 'should return loaded profiles.yml file' do
      write 'profiles.yml', <<-YAML
        development:
          foo: bar
      YAML
      expect(Buildr.settings.profiles).to eq({ 'development'=> { 'foo'=>'bar' } })
    end

    it 'should fail if profiles.yaml file is not a hash' do
      write 'profiles.yaml', 'foo bar'
      expect { Buildr.settings.profiles }.to raise_error(RuntimeError, /expecting.*profiles.yaml/i)
    end

    it 'should be empty hash if profiles.yaml file is empty' do
      write 'profiles.yaml'
      expect(Buildr.settings.profiles).to eq({})
    end
  end

  describe 'profile' do
    before do
    end

    it 'should be empty hash if no profiles.yaml' do
      expect(Buildr.settings.profile).to eq({})
    end

    it 'should be empty hash if no matching profile' do
      write 'profiles.yaml', <<-YAML
        test:
          foo: bar
      YAML
      expect(Buildr.settings.profile).to eq({})
    end

    it 'should return profile matching environment name' do
      write 'profiles.yaml', <<-YAML
        development:
          foo: bar
        test:
          foo: baz
      YAML
      expect(Buildr.settings.profile).to eq({ 'foo'=>'bar' })
    end
  end

  describe 'buildfile task' do
    before do
      @buildfile_time = Time.now - 10
      write 'buildfile'; File.utime(@buildfile_time, @buildfile_time, 'buildfile')
    end

    it 'should point to the buildfile' do
      expect(Buildr.application.buildfile).to point_to_path('buildfile')
    end

    it 'should be a defined task' do
      expect(Buildr.application.buildfile).to eq(file(File.expand_path('buildfile')))
    end

    it 'should ignore any rake namespace' do
      namespace 'dummy_ns' do
        expect(Buildr.application.buildfile).to point_to_path('buildfile')
      end
    end

    it 'should have the same timestamp as the buildfile' do
      expect(Buildr.application.buildfile.timestamp).to be_within(1).of(@buildfile_time)
    end

    it 'should have the same timestamp as build.yaml if the latter is newer' do
      write 'build.yaml'; File.utime(@buildfile_time + 5, @buildfile_time + 5, 'build.yaml')
      Buildr.application.run
      expect(Buildr.application.buildfile.timestamp).to be_within(1).of(@buildfile_time + 5)
    end

    it 'should have the same timestamp as the buildfile if build.yaml is older' do
      write 'build.yaml'; File.utime(@buildfile_time - 5, @buildfile_time - 5, 'build.yaml')
      Buildr.application.run
      expect(Buildr.application.buildfile.timestamp).to be_within(1).of(@buildfile_time)
    end

    it 'should have the same timestamp as build.rb in home dir if the latter is newer (until version 1.6)' do
      expect(Buildr::VERSION).to be < '1.6'
      buildfile_should_have_same_timestamp_as 'home/buildr.rb'
    end

    it 'should have the same timestamp as build.rb in home dir if the latter is newer' do
      buildfile_should_have_same_timestamp_as 'home/.buildr/buildr.rb'
    end

    it 'should have the same timestamp as .buildr.rb in buildfile dir if the latter is newer' do
      buildfile_should_have_same_timestamp_as '.buildr.rb'
    end

    it 'should have the same timestamp as _buildr.rb in buildfile dir if the latter is newer' do
      buildfile_should_have_same_timestamp_as '_buildr.rb'
    end

    def buildfile_should_have_same_timestamp_as(file)
      write file; File.utime(@buildfile_time + 5, @buildfile_time + 5, file)
      Buildr.application.send :load_tasks
      expect(Buildr.application.buildfile.timestamp).to be_within(1).of(@buildfile_time + 5)
    end
  end
end


describe Buildr do

  describe 'environment' do
    it 'should be same as Buildr.application.environment' do
      expect(Buildr.environment).to eql(Buildr.application.environment)
    end
  end

  describe 'application' do
    it 'should be same as Rake.application' do
      expect(Buildr.application).to eq(Rake.application)
    end
  end

  describe 'settings' do
    it 'should be same as Buildr.application.settings' do
      expect(Buildr.settings).to eq(Buildr.application.settings)
    end
  end

end

describe Rake do
  describe 'define_task' do
   it 'should restore call chain when invoke is called' do
     task1 = Rake::Task.define_task('task1') do
     end

     task2 = Rake::Task.define_task('task2') do
       chain1 = Thread.current[:rake_chain]
       task1.invoke
       chain2 = Thread.current[:rake_chain]
       expect(chain2).to eq(chain1)
     end

     task2.invoke
   end
 end
end
