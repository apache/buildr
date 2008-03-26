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

describe Buildr::ArtifactNamespace, 'obtained from Buildr#artifacts' do 
  before :each do 
    ArtifactNamespace.clear
  end
  
  it 'should tap root namespace if called outside a project definition' do
    expected = be_kind_of(ArtifactNamespace)
    artifacts { |ns| ns.name.should == ArtifactNamespace::ROOT }
    artifacts { |ns| ns.should expected }.should expected
    artifacts { self.should expected }
  end

  it 'should tap root namespace when given nil' do
    artifacts(nil) { |ns| ns.name.should == ArtifactNamespace::ROOT }
  end

  it 'should return an array responding to :namespace if no block given' do
    ary = artifacts
    ary.should be_kind_of(Array)
    ary.should respond_to(:namespace)
    ary.namespace.should be_kind_of(ArtifactNamespace)
    ary.namespace.name.should === ArtifactNamespace::ROOT
  end

  it 'should return the namespace for the current project' do
    define 'foo' do
      artifacts { |ns| ns.name.should == name.intern }
      define 'bar' do 
        artifacts { |ns| ns.name.should == name.intern }
      end
    end
  end

  it 'should take the first argument as the scope when given a block' do 
    artifacts('moo') { |ns| ns.name.should == :moo }
    artifacts(:mooo) { |ns| ns.name.should == :mooo }
    a = Module.new { def self.name; "Some::Module::A"; end }
    artifacts(a) { |ns| ns.name.should == "Some:Module:A".intern }
  end  
end

describe Buildr::ArtifactNamespace do 
  before :each do 
    ArtifactNamespace.clear
  end

  it 'should have no parent if its the root namespace' do
    root = artifacts.namespace
    root.parent.should be_nil
  end

  it 'should reference it\'s parent' do
    root = artifacts.namespace
    define 'foo' do
      foo = artifacts { |ns| ns.parent.should == root }
      define 'bar' do
        artifacts { |ns| ns.parent.should == foo }
      end
    end
  end

  it 'should register a requirement with the #need method' do
    artifacts do |root|
      root.need 'foo:bar:jar:>1.0'
      root.should_not be_satisfied('foo:bar:jar:?')
      root.need :bat => 'foo:bat:jar:>1.0'
      root.should_not be_satisfied(:bat)
    end
  end

  it 'should register an artifact with the #use method' do
    artifacts do |root|
      root.use :bat => 'bat:bar:jar:2.0'
      root.spec(:bat).should_not be_nil
      root.spec(:bat)[:version].should == '2.0'
      root.spec(:bat)[:group].should == 'bat'
      artifacts(:bat).should_not be_empty
      root.use 'bat:man:jar:3.0'
      root.spec('bat:man:jar:?')[:version].should == '3.0'
      artifacts('bat:man:jar:?').should_not be_empty
    end
  end

  it 'should set defaults witht the #default method' do 
    artifacts do |root|
      root.use :bar => 'foo:bar:jar:2.0'
      root.spec(:bar).should_not be_nil
      root.default :bar => 'foo:bar:jar:1.9'
      root.spec(:bar)[:version].should == '2.0'
      root.default :baz => 'foo:baz:jar:1.8'
      root.spec(:baz)[:version].should == '1.8'
    end
  end

  it 'should complain if requirement is not met' do 
    artifacts do |root|
      root.need :foo => 'foo:bar:jar:>3.0'
      lambda { root.use :foo => '2.0' }.should raise_error(Exception)
      lambda { root.use :foo => 'foo:baz:jar:3.1' }.should raise_error(Exception)
      root.use :foo => '3.2'
      root.spec(:foo)[:version].should == '3.2'
      root.use :bat => '2.0'
      lambda { root.need :bat => 'foo:bat:jar:>2.0' }.should raise_error(Exception)
      root.use :baz => 'foo:ban:jar:2.1'
      lambda { root.need :baz => 'foo:baz:jar:>2.0' }.should raise_error(Exception)
    end
  end
  
end
