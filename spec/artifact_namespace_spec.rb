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

  it 'should return an array responding to #namespace if no block given' do
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
    artifacts do |ns|
      ns.need 'foo:bar:jar:>1.0'
      ns.should_not be_satisfied('foo:bar:jar:?')
      ns.need :bat => 'foo:bat:jar:>1.0'
      ns.should_not be_satisfied(:bat)
    end
  end

  it 'should register an artifact with the #use method' do
    artifacts do |ns|
      ns.use :bat => 'bat:bar:jar:2.0'
      ns.spec(:bat).should_not be_nil
      ns.spec(:bat)[:version].should == '2.0'
      ns.spec(:bat)[:group].should == 'bat'
      artifacts(:bat).should_not be_empty
      ns.use 'bat:man:jar:3.0'
      ns.spec('bat:man:jar:?')[:version].should == '3.0'
      artifacts('bat:man:jar:?').should_not be_empty
    end
  end

  it 'should set defaults witht the #default method' do 
    artifacts do
      use :bar => 'foo:bar:jar:2.0'
      spec(:bar)[:version].should == '2.0'
      default :bar => 'foo:bar:jar:1.9'
      spec(:bar)[:version].should == '2.0'
      default :baz => 'foo:baz:jar:1.8'
      spec(:baz)[:version].should == '1.8'
      need :bat => 'foo:bat:jar:>1.0'
      default :bat => 'foo:bat:jar:1.5'
      spec(:bat)[:version].should == '1.5'
    end
  end

  it 'should complain if requirement is not met' do 
    artifacts do |ns|
      ns.need :foo => 'foo:bar:jar:>3.0'
      lambda { ns.use :foo => '2.0' }.should raise_error(Exception)
      lambda { ns.use :foo => 'foo:baz:jar:3.1' }.should raise_error(Exception)
      ns.use :foo => '3.2'
      ns.spec(:foo)[:version].should == '3.2'
      ns.use :bat => '2.0'
      lambda { ns.need :bat => 'foo:bat:jar:>2.0' }.should raise_error(Exception)
      ns.use :baz => 'foo:ban:jar:2.1'
      lambda { ns.need :baz => 'foo:baz:jar:>2.0' }.should raise_error(Exception)
    end
  end

  it 'should be populated with ArtifactNamespace.load given a hash of hashes' do 
    hash = {}
    hash[nil] = Hash[:foo => 'foo:bar:jar:1.0']
    hash['one'] = Hash[:foo => 'foo:bar:jar:2.0']
    ArtifactNamespace.load(hash)
    artifacts[nil].spec(:foo)[:version].should == '1.0'
    artifacts['one'].spec(:foo)[:version].should == '2.0'
  end

  it 'should select compatible artifacts defined on parent namespaces' do
    artifacts do
      use :foo => 'foo:bar:jar:3.0'
      use :baz => 'foo:baz:jar:1.0'
      use 'foo:bat:jar:1.5.6.7'
    end
    module Some
      Buildr.artifacts(self) do
        need :foo => 'foo:bar:jar:>=1.0'
        need :baz => 'foo:baz:jar:>=2.0'
        need :bat => 'foo:bat:jar:>1.5 & <1.6'
        default :foo => '2.0'
        default :baz => '2.0'
        default :bat => '1.5.5'
      end
    end
    artifacts[Some].spec(:foo)[:version].should == '3.0'
    artifacts[Some].spec(:baz)[:version].should == '2.0'
    artifacts[Some].spec(:bat)[:version].should == '1.5.6.7'
  end
  
end
