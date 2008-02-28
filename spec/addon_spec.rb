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


describe Addon do
  before { $loaded = false }

  it 'should list all loaded addons' do
    write 'foobar/init.rb'
    addon file('foobar')
    Addon.list.each { |addon| addon.should be_kind_of(Addon) }.
      map(&:name).should include('foobar')
  end

  it 'should return true when loading addon for first time' do
    write 'foobar/init.rb'
    addon(file('foobar')).should be(true)
  end

  it 'should allow loading same addon twice' do
    write 'foobar/init.rb'
    addon file('foobar')
    lambda { addon file('foobar') }.should_not raise_error
  end

  it 'should return false when loading addon second time' do
    write 'foobar/init.rb'
    addon(file('foobar'))
    addon(file('foobar')).should be(false)
  end

  it 'should instantiate addon once even if loaded twice' do
    write 'foobar/init.rb', <<-RUBY
      $loaded = !$loaded
    RUBY
    lambda { addon file('foobar') }.should change { $loaded }
    lambda { addon file('foobar') }.should_not change { $loaded }
  end
end


describe Addon, 'from directory' do
  before { $loaded = false }

  it 'should have no version number' do
  end

  it 'should add directory to LOAD_PATH' do
    mkpath 'foobar'
    lambda { addon file('foobar') }.should change { $LOAD_PATH.clone }
    $LOAD_PATH.should include(File.expand_path('foobar'))
  end

  it 'should load init.rb file if found' do
    write 'foobar/init.rb', '$loaded = true'
    lambda { addon file('foobar') }.should change { $loaded }.to(true)
  end

  it 'should add init.rb to LOADED_FEATURES' do
    write 'foobar/init.rb'
    lambda { addon file('foobar') }.should change { $LOADED_FEATURES.clone }
    $LOADED_FEATURES.should include(File.expand_path('foobar/init.rb'))
  end

  it 'should pass options to addon' do
    write 'foobar/init.rb', '$loaded = $ADDON[:loaded]'
    lambda { addon file('foobar'), :loaded=>5 }.should change { $loaded }.to(5)
  end

  it 'should import any tasks present in tasks sub-directory' do
    write 'foobar/tasks/foo.rake', "$loaded = 'foo'"
    addon file('foobar')
    lambda { Rake.application.load_imports }.should change { $loaded }.to('foo')
  end

  it 'should fail if directory doesn\'t exist' do
    lambda { addon file('missing') }.should raise_error(RuntimeError, /not a directory/i)
  end

  it 'should fail if path is not a directory' do
    write 'wrong'
    lambda { addon file('wrong') }.should raise_error(RuntimeError, /not a directory/i)
  end
end


describe Addon, 'from artifact' do
  before { $loaded = false }

  def load_addon(options = nil)
    write 'source/init.rb', "require 'extra'"
    write 'source/extra.rb', '$loaded = $ADDON[:loaded] || true'
    zip('repository/org/apache/buildr/foobar/1.0/foobar-1.0.zip').include(:from=>'source').invoke
    addon 'org.apache.buildr.foobar:1.0', options
  end

  it 'should figure out addon group from name:version' do
    artifact('fizz.buzz:foobar:zip:1.0').should_receive(:execute)
    addon 'fizz.buzz.foobar:1.0' rescue nil
  end

  it 'should pick name from prefix' do
    load_addon
    Addon.list.map(&:name).should include('org.apache.buildr.foobar')
  end

  it 'should pick version from suffix' do
    load_addon
    Addon.list.map(&:version).should include('1.0')
  end

  it 'should download artifact from remote repository' do
    lambda { addon 'org.apache.buildr.foobar:1.0' }.should raise_error(Exception, /no remote repositories/i)
  end

  it 'should install artifact in local repository' do
    load_addon
    file('repository/org/apache/buildr/foobar/1.0/foobar-1.0.zip').should exist
  end

  it 'should expand ZIP addon into local repository' do
    load_addon
    file('repository/org/apache/buildr/foobar/1.0/foobar-1.0').should exist
    file('repository/org/apache/buildr/foobar/1.0/foobar-1.0').should contain('init.rb', 'extra.rb')
  end

  it 'should add directory to LOAD_PATH' do
    lambda { load_addon  }.should change { $LOAD_PATH.clone }
    $LOAD_PATH.should include(File.expand_path('repository/org/apache/buildr/foobar/1.0/foobar-1.0'))
  end

  it 'should load init.rb file if found' do
    lambda { load_addon }.should change { $loaded }.to(true)
  end

  it 'should add init.rb to LOADED_FEATURES' do
    lambda { load_addon }.should change { $LOADED_FEATURES.clone }
    $LOADED_FEATURES.should include(File.expand_path('repository/org/apache/buildr/foobar/1.0/foobar-1.0/init.rb'))
  end

  it 'should pass options to addon' do
    lambda { load_addon :loaded=>5 }.should change { $loaded }.to(5)
  end

  it 'should fail if loading same addon with two different versions' do
    load_addon
    lambda { addon 'org.apache.buildr.foobar:2.0' }.should raise_error(RuntimeError, /two different version numbers/)
  end

  it 'should import any tasks present in tasks sub-directory' do
    write 'source/tasks/foo.rake', "$loaded = 'foo'"
    load_addon
    lambda { Rake.application.load_imports }.should change { $loaded }.to('foo')
  end
end
