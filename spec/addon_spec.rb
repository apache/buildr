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


describe Buildr, 'addon' do

  before do
    @loaded_specs = Gem.loaded_specs.clone
    Gem.use_paths(Dir.pwd)
    Gem.source_index.load_gems_in Gem::SourceIndex.installed_spec_directories
  end

  before do
    $loaded = nil
  end

  before do
    @available ||= []
    Gem::SourceInfoCache.should_receive(:search).any_number_of_times do |dep|
      @available.select { |spec| spec.name == dep.name && dep.version_requirements.satisfied_by?(spec.version) }.sort_by(&:sort_obj)
    end

    should_receive(:sh).any_number_of_times do |*args|
      unless Gem.win_platform? || RUBY_PLATFORM =~ /java/
        fail 'Expecting sudo gem for this platform' unless args.shift == 'sudo'
      end
      args.shift =~ /ruby/ or fail 'Expecting ruby command'
      args.shift == '-S' or fail 'Expecting -S command line argument'
      args.shift == 'gem' or fail 'Expecting gem script'
      args.shift == 'install' or fail 'Expecting install comamnd'
      (name = args.shift) or fail 'Expecting gem name to come next'
      args.shift == '-v' or fail 'Expecting -v option'
      dep = Gem::Dependency.new(name, args.shift)
      if spec = Gem::SourceInfoCache.search(dep).last
        spec.loaded_from = File.join(Gem.dir, 'specifications', "#{spec.full_name}.gemspec")
        Gem.source_index.add_spec(spec)
        Gem.source_index.should_receive(:load_gems_in).any_number_of_times.with(Gem::SourceIndex.installed_spec_directories)
        spec.files.reject { |file| File.directory?(file) }.each do |file|
          target = File.expand_path(file, spec.full_gem_path)
          mkpath File.dirname(target)
          cp file, target
        end
      else
        fail 'Forget to check source info cache'
      end
    end
  end

  def available(name, version)
    @available << Gem::Specification.new do |s|
      s.platform = Gem::Platform::RUBY
      s.name = name
      s.version = version
      s.author = 'A User'
      s.email = 'example@example.com'
      s.homepage = 'http://example.com'
      s.has_rdoc = true
      s.summary = "this is a summary"
      s.description = "This is a test description"
      s.files = FileList['lib/**/*', 'tasks/**/*']
      yield(s) if block_given?
    end
  end

  it 'should install specified gem' do
    available 'foobar', '1.0.0'
    lambda { addon 'foobar' }.should change { spec = Gem.loaded_specs['foobar'] and spec.full_name }.to('foobar-1.0.0')
  end

  it 'should install version 0 or later' do
    available 'foobar', '0.0.0'
    lambda { addon 'foobar' }.should change { spec = Gem.loaded_specs['foobar'] and spec.full_name }.to('foobar-0.0.0')
  end

  it 'should install specified version number' do
    ['1.0', '1.1', '1.2', '2.0'].each do |version|
      available 'foobar', version
    end
    lambda { addon 'foobar', '1.1' }.should change { spec = Gem.loaded_specs['foobar'] and spec.full_name }.to('foobar-1.1')
  end

  it 'should install version matching requirement' do
    ['1.0', '1.1', '1.2', '2.0'].each do |version|
      available 'foobar', version
    end
    lambda { addon 'foobar', '~> 1' }.should change { spec = Gem.loaded_specs['foobar'] and spec.full_name }.to('foobar-1.2')
  end

  it 'should support array of version matches' do
    ['1.0', '1.1', '1.2'].each do |version|
      available 'foobar', version
    end
    lambda { addon 'foobar', ['> 1.0', '< 1.2'] }.should change { spec = Gem.loaded_specs['foobar'] and spec.full_name }.to('foobar-1.1')
  end

  it 'should complain if no version matches requirement' do
    available 'foobar', '1.0'
    lambda { addon 'foobar', '2.0' }.should raise_error(Gem::LoadError, /could not find/i)
  end

  it 'should complain if installing conflicting versions' do
    available 'foobar', '1.0'
    available 'foobar', '2.0'
    addon 'foobar', '1.0'
    lambda { addon 'foobar', '2.0' }.should raise_error(Exception, /can't activate/)
  end

  it 'should not upgrade if compatible version available in local repository' do
    available 'foobar', '1.0'
    addon 'foobar', '1.0'
    available 'foobar', '2.0'
    addon 'foobar', '1.0'
    Gem.loaded_specs['foobar'].full_name.should eql('foobar-1.0')
  end

  it 'should complain if gem not in remote repository' do
    lambda { addon 'foobar', '1.1' }.should raise_error(Gem::LoadError, /could not find foobar/i)
  end

  it 'should not install gem if already present'

  it 'should require files in gem require path (lib)' do
    write 'lib/foobar.rb', '$loaded = true'
    available 'foobar', '1.0'
    lambda do
      addon 'foobar'
    end.should change { $loaded }.to(true)
  end

  it 'should not require files placed elsewhere in gem' do
    write 'lib/extra/foobar.rb', '$loaded = true'
    available 'foobar', '1.0'
    lambda do
      addon 'foobar'
    end.should_not change { $loaded }
    lambda { require 'extra/foobar.rb' }.should change { $loaded }.to(true)
  end

  it 'should require files only once' do
    write 'lib/foobar.rb', '$loaded = $loaded.to_i + 1'
    available 'foobar', '1.0'
    lambda do
      addon 'foobar'
      addon 'foobar'
    end.should change { $loaded }.to(1)
  end

  it 'should import all .rake files in tasks directory' do
    write 'tasks/test.rake', '$loaded = true'
    available 'foobar', '1.0'
    lambda do
      addon 'foobar'
      Rake.application.load_imports
    end.should change { $loaded }.to(true)
  end

  after do
    Gem.loaded_specs.replace @loaded_specs
  end
end
