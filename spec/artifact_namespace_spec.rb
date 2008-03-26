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

describe Buildr, '#artifacts' do 
  before :each do 
    ArtifactNamespace.clear
  end
  
  it 'should tap root namespace if given a block and called outside a project definition' do
    expected = be_kind_of(ArtifactNamespace)
    artifacts { |ns| ns.name.should == ArtifactNamespace::ROOT }
    artifacts { |ns| ns.should expected }.should expected
  end

  it 'should tap root namespace when given a block and nil argument' do
    artifacts(nil) { |ns| ns.name.should == ArtifactNamespace::ROOT }
  end

  it 'should return an array whose non-numeric indices are namespaces' do
    ary = artifacts("foo:bar:jar:1.0")
    ary.should be_kind_of(Array)
    ary[0].should be_kind_of(Artifact)
    ary[nil].should be_kind_of(ArtifactNamespace)
    ary[nil].name.should === ArtifactNamespace::ROOT
    ary['some:addon'].should be_kind_of(ArtifactNamespace)
    ary['some:addon'].name.should === 'some:addon'.intern
  end

  it 'should take symbols, searching for them on the current namespace' do 
    artifacts[nil][:bar] = 'foo:bar:jar:1.0'
    artifacts[nil].use 'foo:moo:jar:2.0'
    artifacts[nil][:bat] = 'foo:bar:jar:0.9'
    define 'foo' do
      artifacts[project][:baz] = 'foo:baz:jar:1.0'
      compile.with :bar, :baz, :'foo:moo:jar:-', 'some:other:jar:1.0'
      classpath = compile.classpath.map(&:to_spec)
      classpath.should include('foo:baz:jar:1.0', 'foo:bar:jar:1.0', 
                               'foo:moo:jar:2.0', 'some:other:jar:1.0')
      classpath.should_not include('foo:bar:jar:0.9')
    end
  end

  it 'should return the namespace for the current project if given a block' do
    define 'foo' do
      artifacts { |ns| ns.name.should == name.intern }
      define 'bar' do 
        artifacts { |ns| ns.name.should == name.intern }
      end
    end
  end

  it 'should take the first argument as the namespace when given a block' do 
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
    root = artifacts[nil]
    root.parent.should be_nil
  end

  it 'should reference it\'s parent' do
    root = artifacts[nil]
    define 'foo' do
      foo = artifacts { |ns| ns.parent.should == root }
      define 'bar' do
        artifacts { |ns| ns.parent.should == foo }
      end
    end
  end

  it 'should take the artifact id attribute as name' do
     artifacts do |ns|
        ns.need 'foo:bar:jar:>1.0'
        ns.default :bar => '1.1'
        ns.spec('foo:bar:jar:-')[:version].should == '1.1'
        ns.use 'some:thing:jar:2.0'
        ns.spec(:thing)[:version].should == '2.0'
        ns.spec('some:thing:jar:-')[:version].should == '2.0'
     end
  end

  it 'should register a requirement with the #need method' do
    artifacts do |ns|
      ns.need 'foo:bar:jar:>1.0'
      ns.should_not be_satisfied('foo:bar:jar:?')
      ns.need :bat => 'foo:bat:jar:>1.0'
      ns.should_not be_satisfied(:bat)
    end
    artifacts('foo') do |ns|
      ns.need 'foo:baz:jar:>1.0' => '2.0'
      ns.spec('foo:baz:jar:-').values_at(:id, :version).should == ['baz', '2.0']
      ns.spec(:baz).values_at(:id, :version).should == ['baz', '2.0']
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
    artifacts do |ns|
      ns.use :bar => 'foo:bar:jar:2.0'
      ns.spec(:bar)[:version].should == '2.0'
      ns.default :bar => 'foo:bar:jar:1.9'
      ns.spec(:bar)[:version].should == '2.0'
      ns.default :baz => 'foo:baz:jar:1.8'
      ns.spec(:baz)[:version].should == '1.8'
      ns.need :bat => 'foo:bat:jar:>1.0'
      ns.default :bat => 'foo:bat:jar:1.5'
      ns.spec(:bat)[:version].should == '1.5'
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
    artifacts do |ns|
      ns.use :foo => 'foo:bar:jar:3.0'
      ns.use :baz => 'foo:baz:jar:1.0'
      ns.use 'foo:bat:jar:1.5.6.7'
    end
    module Some
      Buildr.artifacts(self) do |ns|
        ns.need :foo => 'foo:bar:jar:>=1.0'
        ns.need :baz => 'foo:baz:jar:>=2.0'
        ns.need :bat => 'foo:bat:jar:>1.5 & <1.6'
        ns.default :foo => '2.0'
        ns.default :baz => '2.0'
        ns.default :bat => '1.5.5'
      end
    end
    artifacts[Some].spec(:foo)[:version].should == '3.0'
    artifacts[Some].spec(:baz)[:version].should == '2.0'
    artifacts[Some].spec(:bat)[:version].should == '1.5.6.7'
  end

  it 'should return its artifacts when called the #values method' do
    artifacts do |ns|
      ns.use "num:one:jar:1.1", "num:two:jar:2.2"
    end
    artifacts('foo') do |ns|
      ns.need :one => 'num:one:jar:>=1.0'
      ns.default :one => '1.0'
      ns.need :three => 'num:three:jar:>=3.0'
      ns.default :three => '3.0'
    end
    foo = artifacts['foo'].values.map(&:to_spec)
    foo.should include("num:one:jar:1.1", "num:three:jar:3.0")
    foo = artifacts['foo'].values(true).map(&:to_spec) # including parents
    foo.should include("num:one:jar:1.1", "num:three:jar:3.0", "num:two:jar:2.2")
    artifacts['foo'].need :four => 'num:four:jar:>4.0'
    lambda { artifacts[:foo].values }.should raise_error(Exception, /no version/i)
    foo = artifacts['foo'].values(false, true).map(&:to_spec) # ignore missing
    foo.should include("num:one:jar:1.1", "num:three:jar:3.0")
  end

end
