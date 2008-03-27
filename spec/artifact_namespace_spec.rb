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

require 'java/artifact_namespace'

describe Buildr::ArtifactNamespace do

  before(:each) { Buildr::ArtifactNamespace.clear }

  def abc_module
    Object.module_eval 'module A; module B; module C; end; end; end'
    yield
  ensure
    Object.send :remove_const, :A
  end

  describe '.root' do 
    it 'should return the top level namespace' do
      Buildr::ArtifactNamespace.root.should be_root
    end
    
    it 'should yield the namespace if a block is given' do
      Buildr::ArtifactNamespace.root { |ns| ns.should be_root }
    end
  end

  describe '.instance' do 
    it 'should return the top level namespace when invoked outside a project definition' do
      artifact_ns.should be_root
    end
    
    it 'should return the current project namespace when invoked inside a project' do
      define 'foo' do
        artifact_ns.should_not be_root
        artifact_ns.name.should == :foo
        task :doit do 
          artifact_ns.should_not be_root
          artifact_ns.name.should == :foo
        end.invoke
      end
    end
  
    it 'should return the root namespace if given :root' do
      artifact_ns(:root).should be_root
    end
    
    it 'should return the namespace for the given name' do 
      artifact_ns(:foo).name.should == :foo
      artifact_ns('foo:bar').name.should == 'foo:bar'.intern
      artifact_ns(['foo', 'bar', 'baz']).name.should == 'foo:bar:baz'.intern
      abc_module do 
        artifact_ns(A::B::C).name.should == 'A:B:C'.intern
      end
      artifact_ns(:root).should be_root
      artifact_ns(:current).should be_root
      define 'foo' do
        artifact_ns(:current).name.should == :foo
        define 'baz' do
          artifact_ns(:current).name.should == 'foo:baz'.intern
        end
      end
    end
  end

  describe '#parent' do 
    it 'should be nil for root namespace' do 
      artifact_ns(:root).parent.should be_nil
    end
    
    it 'should be the parent namespace for nested modules' do 
      abc_module do
        artifact_ns(A::B::C).parent.should == artifact_ns(A::B)
        artifact_ns(A::B).parent.should == artifact_ns(A)
        artifact_ns(A).parent.should == artifact_ns(:root)
      end
    end

    it 'should be the parent namespace for nested projects' do
      define 'a' do 
        define 'b' do 
          define 'c' do
            artifact_ns.parent.should == artifact_ns(parent)
          end
          artifact_ns.parent.should == artifact_ns(parent)
        end
        artifact_ns.parent.should == artifact_ns(:root)
      end
    end
  end
  
  describe '#parent=' do
    it 'should reject to set parent for root namespace' do 
      lambda { artifact_ns(:root).parent = :foo }.should raise_error(Exception, /cannot set parent/i)
    end

    it 'should allow to set parent' do
      artifact_ns(:bar).parent = :foo
      artifact_ns(:bar).parent.should == artifact_ns(:foo)
      artifact_ns(:bar).parent = artifact_ns(:baz)
      artifact_ns(:bar).parent.should == artifact_ns(:baz)
    end

    it 'should allow to set parent to :current' do
      abc_module do 
        mod = A::B
        artifact_ns(mod).parent = :current
        def mod.stuff 
          Buildr::artifact_ns(self)
        end
        define 'a' do
          define 'b' do
            mod.stuff.parent.should == artifact_ns
          end
          mod.stuff.parent.should == artifact_ns
        end
      end
    end
  end
  
  describe '#need' do 
    it 'should accept an artifact spec' do
      define 'one' do
        artifact_ns.need 'a:b:c:1'
        # referenced by spec
        artifact_ns['a:b:c'].should_not be_selected
        
        # referenced by name
        artifact_ns[:b].should_not be_selected
        artifact_ns[:b].should be_satisfied_by('a:b:c:1')
        artifact_ns[:b].should_not be_satisfied_by('a:b:c:2')
        artifact_ns[:b].should_not be_satisfied_by('d:b:c:1')
        artifact_ns[:b].version.should == '1'
      end
    end

    it 'should accept a requirement_spec' do
      define 'one' do
        artifact_ns.need 'thing -> a:b:c:2.1 -> ~>2.0'
        # referenced by spec
        artifact_ns['a:b:c'].should_not be_selected
        
        # referenced by name
        artifact_ns.key?(:b).should be_false
        artifact_ns[:thing].should_not be_selected
        artifact_ns[:thing].should be_satisfied_by('a:b:c:2.5')
        artifact_ns[:thing].should_not be_satisfied_by('a:b:c:3')
        artifact_ns[:thing].version.should == '2.1'
      end
    end

    it 'should accept a hash :name -> requirement_spec' do 
      define 'one' do
        artifact_ns.need :thing => 'a:b:c:2.1 -> ~>2.0'
        artifact_ns[:thing].should be_satisfied_by('a:b:c:2.5')
        artifact_ns[:thing].should_not be_satisfied_by('a:b:c:3')
        artifact_ns[:thing].version.should == '2.1'
      end

      define 'two' do
        artifact_ns.need :thing => 'a:b:c:(~>2.0 | 2.1)'
        artifact_ns[:thing].should be_satisfied_by('a:b:c:2.5')
        artifact_ns[:thing].should_not be_satisfied_by('a:b:c:3')
        artifact_ns[:thing].version.should == '2.1'
      end
    end

    it 'should take a hash :name -> specs_array' do 
      define 'one' do 
        artifact_ns.need :things => ['foo:bar:jar:1.0',
                                     'foo:baz:jar:2.0',]
        artifact_ns['foo:bar:jar'].should_not be_selected
        artifact_ns['foo:baz:jar'].should_not be_selected
        artifact_ns[:bar, :baz].should == [nil, nil]
        artifact_ns[:things].map(&:unversioned_spec).should include('foo:bar:jar', 'foo:baz:jar')
        artifact_ns.alias :baz, 'foo:baz:jar'
        artifact_ns[:baz].should == artifact_ns['foo:baz:jar']
      end
    end

    it 'should select best matching version if defined' do 
      define 'one' do 
        artifact_ns.use :a => 'foo:bar:jar:1.5'
        artifact_ns.use :b => 'foo:baz:jar:2.0'
        define 'two' do
          artifact_ns[:a].requirement.should be_nil
          artifact_ns[:a].should be_selected

          artifact_ns.need :c => 'foo:bat:jar:3.0'
          artifact_ns['foo:bat:jar'].should_not be_selected
          artifact_ns[:c].should_not be_selected
          
          artifact_ns.need :one => 'foo:bar:jar:>=1.0'
          artifact_ns[:one].version.should == '1.5'
          artifact_ns[:one].should be_selected
          artifact_ns[:a].requirement.should be_nil

          artifact_ns.need :two => 'foo:baz:jar:>2'
          artifact_ns[:two].version.should be_nil
          artifact_ns[:two].should_not be_selected
          artifact_ns[:b].requirement.should be_nil
        end
      end
    end
  end

  describe '#use' do 
    it 'should register the artifact on namespace' do
      define 'one' do
        artifact_ns.use :thing => 'a:b:c:1'
        artifact_ns[:thing].requirement.should be_nil
        artifact_ns[:thing].version.should == '1'
        artifact_ns[:thing].id.should == 'b'
        define 'one' do
          artifact_ns.use :thing => 'a:d:c:2'
          artifact_ns[:thing].requirement.should be_nil
          artifact_ns[:thing].version.should == '2'
          artifact_ns[:thing].id.should == 'd'
          
          artifact_ns.use :copied => artifact_ns.parent[:thing]
          artifact_ns[:copied].should_not == artifact_ns.parent[:thing]
          artifact_ns[:copied].requirement.should be_nil
          artifact_ns[:copied].version.should == '1'
          artifact_ns[:copied].id.should == 'b'

          artifact_ns.use :aliased => :copied
          artifact_ns[:aliased].should == artifact_ns[:copied]

          lambda { artifact_ns.use :invalid => :unknown }.should raise_error(NameError, /undefined/i)
        end
        artifact_ns[:copied].should be_nil
      end
    end
    
    it 'should complain if namespace requirement is not satisfied' do
      define 'one' do
        artifact_ns.need :bar => 'foo:bar:baz:~>1.5'
        lambda { artifact_ns.use :bar => '1.4' }.should raise_error(Exception, /unsatisfied/i)
      end
    end

    it 'should be able to register a group' do 
      specs = ['its:me:here:1', 'its:you:there:2']
      artifact_ns.use :them => specs
      artifact_ns[:them].map(&:to_spec).should == specs
      artifact_ns['its:me:here'].should_not be_nil
      artifact_ns[:you].should be_nil
    end

    it 'should be able to assign sub namespaces' do 
      artifact_ns(:foo).bar = "foo:bar:baz:0"
      artifact_ns(:moo).foo = artifact_ns(:foo)
      artifact_ns(:moo).foo.should == artifact_ns(:foo)
      artifact_ns(:moo).foo_bar.should == artifact_ns(:foo).bar
    end

  end

  describe '#values' do 
    it 'returns the artifacts defined on namespace' do 
      define 'foo' do
        artifact_ns.use 'foo:one:baz:1.0'
        define 'bar' do
          artifact_ns.use 'foo:two:baz:1.0'
          
          specs = artifact_ns.values.map(&:to_spec)
          specs.should include('foo:two:baz:1.0')
          specs.should_not include('foo:one:baz:1.0')

          specs = artifact_ns.values(true).map(&:to_spec)
          specs.should include('foo:two:baz:1.0', 'foo:one:baz:1.0')
        end
      end
    end
  end
  
  describe '#method_missing' do 
    it 'should use cool_aid! to create a requirement' do 
      define 'foo' do
        artifact_ns.cool_aid!('cool:aid:jar:2').should be_kind_of(ArtifactNamespace::ArtifactRequirement)
        artifact_ns[:cool_aid].version.should == '2'
        artifact_ns[:cool_aid].should_not be_selected
        define 'bar' do 
          artifact_ns.cool_aid! 'cool:aid:man:3', '>2'
          artifact_ns[:cool_aid].version.should == '3'
          artifact_ns[:cool_aid].requirement.should be_satisfied_by('2.5')
          artifact_ns[:cool_aid].should_not be_selected
        end
      end
    end

    it 'should use cool_aid= as shorhand for [:cool_aid]=' do 
      artifact_ns.cool_aid = 'cool:aid:jar:1'
      artifact_ns[:cool_aid].should be_selected
    end
    
    it 'should use cool_aid as shorthand for [:cool_aid]' do
      artifact_ns.need :cool_aid => 'cool:aid:jar:1'
      artifact_ns.cool_aid.should_not be_selected
    end

    it 'should use cool_aid? to test if artifact has been defined and selected' do
      artifact_ns.need :cool_aid => 'cool:aid:jar:>1'
      artifact_ns.should_not have_cool_aid
      artifact_ns.should_not have_unknown
      artifact_ns.cool_aid = '2'
      artifact_ns.should have_cool_aid
    end
  end

  describe '#ns' do 
    it 'should create a sub namespace' do
      artifact_ns.ns :foo
      artifact_ns[:foo].should be_kind_of(ArtifactNamespace)
      artifact_ns(:foo).should_not === artifact_ns.foo
      artifact_ns.foo.parent.should == artifact_ns
    end
    
    it 'should take any use arguments' do
      artifact_ns.ns :foo, :bar => 'foo:bar:jar:0', :baz => 'foo:baz:jar:0'
      artifact_ns.foo.bar.should be_selected
      artifact_ns.foo[:baz].should be_selected
    end
    
    it 'should access sub artifacts using with foo_bar like syntax' do 
      artifact_ns.ns :foo, :bar => 'foo:bar:jar:0', :baz => 'foo:baz:jar:0'
      artifact_ns[:foo_baz].should be_selected
      artifact_ns.foo_bar.should be_selected
      
      artifact_ns.foo.ns :bat, 'bat:man:jar:>1'
      batman = artifact_ns.foo.bat.man
      batman.should be_selected
      artifact_ns[:foo_bat_man] = '3'
      artifact_ns[:foo_bat_man].should == batman
      artifact_ns[:foo_bat_man].version.should == '3'
    end

    it 'should include sub artifacts when calling #values' do 
      artifact_ns.ns :bat, 'bat:man:jar:>1'
      artifact_ns.values.should_not be_empty
      artifact_ns.values.first.unversioned_spec.should == 'bat:man:jar'
    end

    it 'should reopen a sub-namespace' do
      artifact_ns.ns :bat, 'bat:man:jar:>1'
      bat = artifact_ns[:bat]
      bat.should == artifact_ns.ns(:bat)
    end

    it 'should fail reopening if not a sub-namespace' do
      artifact_ns.foo = 'foo:bar:baz:0'
      lambda { artifact_ns.ns(:foo) }.should raise_error(TypeError, /not a sub/i)
    end

    it 'should clone artifacts when assigned' do 
      artifact_ns(:foo).bar = "foo:bar:jar:0"
      artifact_ns(:moo).ns :muu, :miu => artifact_ns(:foo).bar
      artifact_ns(:moo).muu.miu.should_not == artifact_ns(:foo).bar
      artifact_ns(:moo).muu.miu.to_spec.should == artifact_ns(:foo).bar.to_spec
    end
    
    it 'should clone parent artifacts by name' do
      define 'foo' do
        artifact_ns.bar = "foo:bar:jar:0"
        define 'moo' do
          artifact_ns.ns(:muu).use :bar
          artifact_ns.muu_bar.should be_selected
          artifact_ns.muu.bar.should_not == artifact_ns.bar
        end
      end
    end
  end

  it 'should be an Enumerable' do
    artifact_ns.should be_kind_of(Enumerable)
    artifact_ns.use 'foo:bar:baz:1.0'
    artifact_ns.map(&:artifact).should include(artifact('foo:bar:baz:1.0'))
  end

end # ArtifactNamespace

describe Buildr do
  before(:each) { Buildr::ArtifactNamespace.clear }

  describe '.artifacts' do 
    it 'should take ruby symbols and ask the current namespace for them' do
      define 'foo' do 
        artifact_ns.cool = 'cool:aid:jar:1.0'
        artifact_ns.use 'some:other:jar:1.0'
        artifact_ns.use 'bat:man:jar:1.0'
        compile.with :cool, :other, :'bat:man:jar'
        compile.classpath.map(&:to_spec).should include('cool:aid:jar:1.0', 'some:other:jar:1.0', 'bat:man:jar:1.0')
      end
    end
    
    it 'should take a namespace' do 
      artifact_ns(:moo).muu = 'moo:muu:jar:1.0'
      define 'foo' do
        compile.with artifact_ns(:moo)
        compile.classpath.map(&:to_spec).should include('moo:muu:jar:1.0')
      end
    end
  end
  
  describe '.artifact' do
    it 'should search current namespace if given a symbol' do 
      define 'foo' do 
        artifact_ns.use :cool => 'cool:aid:jar:1.0'
        define 'bar' do
          artifact(:cool).should == artifact_ns[:cool].artifact
        end
      end
    end
    
    it 'should search current namespace if given a symbol spec' do 
      define 'foo' do 
        artifact_ns.use 'cool:aid:jar:1.0'
        define 'bar' do
          artifact(:'cool:aid:jar').should == artifact_ns[:aid].artifact
        end
      end
    end
    
    it 'should fail when no artifact by that name is found' do
      define 'foo' do 
        artifact_ns.use 'cool:aid:jar:1.0'
        define 'bar' do
          lambda { artifact(:cool) }.should raise_error(IndexError, /artifact/)
        end
      end
    end
  end
end
