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
      expect(Buildr::ArtifactNamespace.root).to be_root
    end

    it 'should yield the namespace if a block is given' do
      flag = false
      Buildr::ArtifactNamespace.root { |ns| flag = true; expect(ns).to be_root }
      expect(flag).to eq(true)
    end

    it 'should return the root when used outside of a project definition' do
      expect(artifact_ns).to be_root
    end

    it 'should yield to a block when used outside of a project definition' do
      flag = false
      artifact_ns {|ns| flag = true; expect(ns).to be_root}
      expect(flag).to eq(true)
    end
  end

  describe '.instance' do
    it 'should return the top level namespace when invoked outside a project definition' do
      expect(artifact_ns).to be_root
    end

    it 'should return the namespace for the receiving project' do
      define('foo') { }
      expect(project('foo').artifact_ns.name).to eq('foo')
    end

    it 'should return the current project namespace when invoked inside a project' do
      define 'foo' do
        expect(artifact_ns).not_to be_root
        expect(artifact_ns.name).to eq('foo')
        task :doit do
          expect(artifact_ns).not_to be_root
          expect(artifact_ns.name).to eq('foo')
        end.invoke
      end
    end

    it 'should return the root namespace if given :root' do
      expect(artifact_ns(:root)).to be_root
    end

    it 'should return the namespace for the given name' do
      expect(artifact_ns(:foo).name).to eq('foo')
      expect(artifact_ns('foo:bar').name).to eq('foo:bar')
      expect(artifact_ns(['foo', 'bar', 'baz']).name).to eq('foo:bar:baz')
      abc_module do
        expect(artifact_ns(A::B::C).name).to eq('A::B::C')
      end
      expect(artifact_ns(:root)).to be_root
      expect(artifact_ns(:current)).to be_root
      define 'foo' do
        expect(artifact_ns(:current).name).to eq('foo')
        define 'baz' do
          expect(artifact_ns(:current).name).to eq('foo:baz')
        end
      end
    end
  end

  describe '#parent' do
    it 'should be nil for root namespace' do
      expect(artifact_ns(:root).parent).to be_nil
    end

    it 'should be the parent namespace for nested modules' do
      abc_module do
        expect(artifact_ns(A::B::C).parent).to eq(artifact_ns(A::B))
        expect(artifact_ns(A::B).parent).to eq(artifact_ns(A))
        expect(artifact_ns(A).parent).to eq(artifact_ns(:root))
      end
    end

    it 'should be the parent namespace for nested projects' do
      define 'a' do
        define 'b' do
          define 'c' do
            expect(artifact_ns.parent).to eq(artifact_ns(parent))
          end
          expect(artifact_ns.parent).to eq(artifact_ns(parent))
        end
        expect(artifact_ns.parent).to eq(artifact_ns(:root))
      end
    end
  end

  describe '#parent=' do
    it 'should reject to set parent for root namespace' do
      expect { artifact_ns(:root).parent = :foo }.to raise_error(Exception, /cannot set parent/i)
    end

    it 'should allow to set parent' do
      artifact_ns(:bar).parent = :foo
      expect(artifact_ns(:bar).parent).to eq(artifact_ns(:foo))
      artifact_ns(:bar).parent = artifact_ns(:baz)
      expect(artifact_ns(:bar).parent).to eq(artifact_ns(:baz))
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
            expect(mod.stuff.parent).to eq(artifact_ns)
          end
          expect(mod.stuff.parent).to eq(artifact_ns)
        end
      end
    end
  end

  describe '#need' do
    it 'should accept an artifact spec' do
      define 'one' do
        artifact_ns.need 'a:b:c:1'
        # referenced by spec
        expect(artifact_ns['a:b:c']).not_to be_selected

        # referenced by name
        expect(artifact_ns[:b]).not_to be_selected
        expect(artifact_ns[:b]).to be_satisfied_by('a:b:c:1')
        expect(artifact_ns[:b]).not_to be_satisfied_by('a:b:c:2')
        expect(artifact_ns[:b]).not_to be_satisfied_by('d:b:c:1')
        expect(artifact_ns[:b].version).to eq('1')
      end
    end

    it 'should accept an artifact spec with classifier' do
      define 'one' do
        artifact_ns.need 'a:b:c:d:1'
        # referenced by spec
        expect(artifact_ns['a:b:c:d:']).not_to be_selected

        # referenced by name
        expect(artifact_ns[:b]).not_to be_selected
        expect(artifact_ns[:b]).to be_satisfied_by('a:b:c:d:1')
        expect(artifact_ns[:b]).not_to be_satisfied_by('a:b:c:d:2')
        expect(artifact_ns[:b]).not_to be_satisfied_by('d:b:c:d:1')
        expect(artifact_ns[:b].version).to eq('1')
      end
    end

    it 'should accept a requirement_spec' do
      define 'one' do
        artifact_ns.need 'thing -> a:b:c:2.1 -> ~>2.0'
        # referenced by spec
        expect(artifact_ns['a:b:c']).not_to be_selected

        # referenced by name
        expect(artifact_ns.key?(:b)).to be_falsey
        expect(artifact_ns[:thing]).not_to be_selected
        expect(artifact_ns[:thing]).to be_satisfied_by('a:b:c:2.5')
        expect(artifact_ns[:thing]).not_to be_satisfied_by('a:b:c:3')
        expect(artifact_ns[:thing].version).to eq('2.1')
      end
    end

    it 'should accept a hash :name -> requirement_spec' do
      define 'one' do
        artifact_ns.need :thing => 'a:b:c:2.1 -> ~>2.0'
        expect(artifact_ns[:thing]).to be_satisfied_by('a:b:c:2.5')
        expect(artifact_ns[:thing]).not_to be_satisfied_by('a:b:c:3')
        expect(artifact_ns[:thing].version).to eq('2.1')
      end

      define 'two' do
        artifact_ns.need :thing => 'a:b:c:(~>2.0 | 2.1)'
        expect(artifact_ns[:thing]).to be_satisfied_by('a:b:c:2.5')
        expect(artifact_ns[:thing]).not_to be_satisfied_by('a:b:c:3')
        expect(artifact_ns[:thing].version).to eq('2.1')
      end
    end

    it 'should take a hash :name -> specs_array' do
      define 'one' do
        artifact_ns.need :things => ['foo:bar:jar:1.0',
                                     'foo:baz:jar:2.0',]
        expect(artifact_ns['foo:bar:jar']).not_to be_selected
        expect(artifact_ns['foo:baz:jar']).not_to be_selected
        expect(artifact_ns[:bar, :baz]).to eq([nil, nil])
        expect(artifact_ns[:things].map(&:unversioned_spec)).to include('foo:bar:jar', 'foo:baz:jar')
        artifact_ns.alias :baz, 'foo:baz:jar'
        expect(artifact_ns[:baz]).to eq(artifact_ns['foo:baz:jar'])
      end
    end

    it 'should select best matching version if defined' do
      define 'one' do
        artifact_ns.use :a => 'foo:bar:jar:1.5'
        artifact_ns.use :b => 'foo:baz:jar:2.0'
        define 'two' do
          expect(artifact_ns[:a].requirement).to be_nil
          expect(artifact_ns[:a]).to be_selected

          artifact_ns.need :c => 'foo:bat:jar:3.0'
          expect(artifact_ns['foo:bat:jar']).not_to be_selected
          expect(artifact_ns[:c]).not_to be_selected

          artifact_ns.need :one => 'foo:bar:jar:>=1.0'
          expect(artifact_ns[:one].version).to eq('1.5')
          expect(artifact_ns[:one]).to be_selected
          expect(artifact_ns[:a].requirement).to be_nil

          artifact_ns.need :two => 'foo:baz:jar:>2'
          expect(artifact_ns[:two].version).to be_nil
          expect(artifact_ns[:two]).not_to be_selected
          expect(artifact_ns[:b].requirement).to be_nil
        end
      end
    end
  end

  describe '#use' do
    it 'should register the artifact on namespace' do
      define 'one' do
        artifact_ns.use :thing => 'a:b:c:1'
        expect(artifact_ns[:thing].requirement).to be_nil
        expect(artifact_ns[:thing].version).to eq('1')
        expect(artifact_ns[:thing].id).to eq('b')
        define 'one' do
          artifact_ns.use :thing => 'a:d:c:2'
          expect(artifact_ns[:thing].requirement).to be_nil
          expect(artifact_ns[:thing].version).to eq('2')
          expect(artifact_ns[:thing].id).to eq('d')

          artifact_ns.use :copied => artifact_ns.parent[:thing]
          expect(artifact_ns[:copied]).not_to eq(artifact_ns.parent[:thing])
          expect(artifact_ns[:copied].requirement).to be_nil
          expect(artifact_ns[:copied].version).to eq('1')
          expect(artifact_ns[:copied].id).to eq('b')

          artifact_ns.use :aliased => :copied
          expect(artifact_ns[:aliased]).to eq(artifact_ns[:copied])

          expect { artifact_ns.use :invalid => :unknown }.to raise_error(NameError, /undefined/i)
        end
        expect(artifact_ns[:copied]).to be_nil
      end
    end

    it 'should register two artifacts with different version on namespace' do
      define 'one' do
        artifact_ns.use :foo => 'a:b:c:1'
        artifact_ns.use :bar => 'a:b:c:2'
        expect(artifact_ns[:foo].version).to eq('1')
        expect(artifact_ns[:bar].version).to eq('2')
        # unversioned references the last version set.
        expect(artifact_ns['a:b:c'].version).to eq('2')
      end
    end

    it 'should complain if namespace requirement is not satisfied' do
      define 'one' do
        artifact_ns.need :bar => 'foo:bar:baz:~>1.5'
        expect { artifact_ns.use :bar => '1.4' }.to raise_error(Exception, /unsatisfied/i)
      end
    end

    it 'should be able to register a group' do
      specs = ['its:me:here:1', 'its:you:there:2']
      artifact_ns.use :them => specs
      expect(artifact_ns[:them].map(&:to_spec)).to eq(specs)
      expect(artifact_ns['its:me:here']).not_to be_nil
      expect(artifact_ns[:you]).to be_nil
    end

    it 'should be able to assign sub namespaces' do
      artifact_ns(:foo).bar = "foo:bar:baz:0"
      artifact_ns(:moo).foo = artifact_ns(:foo)
      expect(artifact_ns(:moo).foo).to eq(artifact_ns(:foo))
      expect(artifact_ns(:moo).foo_bar).to eq(artifact_ns(:foo).bar)
    end

    it 'should handle symbols with dashes and periods' do
      [:'a-b', :'a.b'].each do |symbol|
        artifact_ns.use symbol => 'a:b:c:1'
        expect(artifact_ns[symbol].version).to eq('1')
        expect(artifact_ns[symbol].id).to eq('b')
      end
    end

    it 'should handle version string' do
      foo = artifact_ns do |ns|
        ns.bar = 'a:b:c:1'
      end
      foo.use :bar => '2.0'
      expect(foo.bar.version).to eq('2.0')
    end
  end

  describe '#values' do
    it 'returns the artifacts defined on namespace' do
      define 'foo' do
        artifact_ns.use 'foo:one:baz:1.0'
        define 'bar' do
          artifact_ns.use 'foo:two:baz:1.0'

          specs = artifact_ns.values.map(&:to_spec)
          expect(specs).to include('foo:two:baz:1.0')
          expect(specs).not_to include('foo:one:baz:1.0')

          specs = artifact_ns.values(true).map(&:to_spec)
          expect(specs).to include('foo:two:baz:1.0', 'foo:one:baz:1.0')
        end
      end
    end
  end

  describe '#values_at' do
    it 'returns the named artifacts' do
      define 'foo' do
        artifact_ns.use 'foo:one:baz:1.0'
        define 'bar' do
          artifact_ns.use :foo_baz => 'foo:two:baz:1.0'

          specs = artifact_ns.values_at('one').map(&:to_spec)
          expect(specs).to include('foo:one:baz:1.0')
          expect(specs).not_to include('foo:two:baz:1.0')

          specs = artifact_ns.values_at('foo_baz').map(&:to_spec)
          expect(specs).to include('foo:two:baz:1.0')
          expect(specs).not_to include('foo:one:baz:1.0')
        end
      end
    end

    it 'returns first artifacts by their unversioned spec' do
      define 'foo' do
        artifact_ns.use 'foo:one:baz:2.0'
        define 'bar' do
          artifact_ns.use :older => 'foo:one:baz:1.0'

          specs = artifact_ns.values_at('foo:one:baz').map(&:to_spec)
          expect(specs).to include('foo:one:baz:1.0')
          expect(specs).not_to include('foo:one:baz:2.0')
        end
        specs = artifact_ns.values_at('foo:one:baz').map(&:to_spec)
        expect(specs).to include('foo:one:baz:2.0')
        expect(specs).not_to include('foo:one:baz:1.0')
      end
    end

    it 'return first artifact satisfying a dependency' do
      define 'foo' do
        artifact_ns.use 'foo:one:baz:2.0'
        define 'bar' do
          artifact_ns.use :older => 'foo:one:baz:1.0'

          specs = artifact_ns.values_at('foo:one:baz:>1.0').map(&:to_spec)
          expect(specs).to include('foo:one:baz:2.0')
          expect(specs).not_to include('foo:one:baz:1.0')
        end
      end
    end
  end

  describe '#artifacts' do
    it 'returns artifacts in namespace' do
      define 'one' do
        artifact_ns[:foo] = 'group:foo:jar:1'
        artifact_ns[:bar] = 'group:bar:jar:1'
        expect(artifact_ns.artifacts.map{|a| a.to_spec}).to include('group:foo:jar:1', 'group:bar:jar:1')
      end
    end
  end

  describe '#keys' do
    it 'returns names in namespace' do
      define 'one' do
        artifact_ns[:foo] = 'group:foo:jar:1'
        artifact_ns[:bar] = 'group:bar:jar:1'
        expect(artifact_ns.keys).to include('foo', 'bar')
      end
    end
  end

  describe '#delete' do
    it 'deletes corresponding artifact requirement' do
      define 'one' do
        artifact_ns[:foo] = 'group:foo:jar:1'
        artifact_ns[:bar] = 'group:bar:jar:1'
        artifact_ns.delete :bar
        expect(artifact_ns.artifacts.map{|a| a.to_spec}).to include('group:foo:jar:1')
        expect(artifact_ns[:foo].to_spec).to eql('group:foo:jar:1')
      end
    end
  end

  describe '#clear' do
    it 'clears all artifact requirements in namespace' do
      define 'one' do
        artifact_ns[:foo] = 'group:foo:jar:1'
        artifact_ns[:bar] = 'group:bar:jar:1'
        artifact_ns.clear
        expect(artifact_ns.artifacts).to be_empty
      end
    end
  end

  describe '#method_missing' do
    it 'should use cool_aid! to create a requirement' do
      define 'foo' do
        expect(artifact_ns.cool_aid!('cool:aid:jar:2')).to be_kind_of(ArtifactNamespace::ArtifactRequirement)
        expect(artifact_ns[:cool_aid].version).to eq('2')
        expect(artifact_ns[:cool_aid]).not_to be_selected
        define 'bar' do
          artifact_ns.cool_aid! 'cool:aid:man:3', '>2'
          expect(artifact_ns[:cool_aid].version).to eq('3')
          expect(artifact_ns[:cool_aid].requirement).to be_satisfied_by('2.5')
          expect(artifact_ns[:cool_aid]).not_to be_selected
        end
      end
    end

    it 'should use cool_aid= as shorhand for [:cool_aid]=' do
      artifact_ns.cool_aid = 'cool:aid:jar:1'
      expect(artifact_ns[:cool_aid]).to be_selected
    end

    it 'should use cool_aid as shorthand for [:cool_aid]' do
      artifact_ns.need :cool_aid => 'cool:aid:jar:1'
      expect(artifact_ns.cool_aid).not_to be_selected
    end

    it 'should use cool_aid? to test if artifact has been defined and selected' do
      artifact_ns.need :cool_aid => 'cool:aid:jar:>1'
      expect(artifact_ns.has_cool_aid?).to be_falsey
      expect(artifact_ns.has_unknown?).to be_falsey
      artifact_ns.cool_aid = '2'
      expect(artifact_ns.has_cool_aid?).to be_truthy
    end
  end

  describe '#ns' do
    it 'should create a sub namespace' do
      artifact_ns.ns :foo
      expect(artifact_ns[:foo]).to be_kind_of(ArtifactNamespace)
      expect(artifact_ns(:foo)).not_to be === artifact_ns.foo
      expect(artifact_ns.foo.parent).to eq(artifact_ns)
    end

    it 'should take any use arguments' do
      artifact_ns.ns :foo, :bar => 'foo:bar:jar:0', :baz => 'foo:baz:jar:0'
      expect(artifact_ns.foo.bar).to be_selected
      expect(artifact_ns.foo[:baz]).to be_selected
    end

    it 'should access sub artifacts using with foo_bar like syntax' do
      artifact_ns.ns :foo, :bar => 'foo:bar:jar:0', :baz => 'foo:baz:jar:0'
      expect(artifact_ns[:foo_baz]).to be_selected
      expect(artifact_ns.foo_bar).to be_selected

      artifact_ns.foo.ns :bat, 'bat:man:jar:>1'
      batman = artifact_ns.foo.bat.man
      expect(batman).to be_selected
      artifact_ns[:foo_bat_man] = '3'
      expect(artifact_ns[:foo_bat_man]).to eq(batman)
      expect(artifact_ns[:foo_bat_man].version).to eq('3')
    end

    it 'should include sub artifacts when calling #values' do
      artifact_ns.ns :bat, 'bat:man:jar:>1'
      expect(artifact_ns.values).not_to be_empty
      expect(artifact_ns.values.first.unversioned_spec).to eq('bat:man:jar')
    end

    it 'should reopen a sub-namespace' do
      artifact_ns.ns :bat, 'bat:man:jar:>1'
      bat = artifact_ns[:bat]
      expect(bat).to eq(artifact_ns.ns(:bat))
    end

    it 'should fail reopening if not a sub-namespace' do
      artifact_ns.foo = 'foo:bar:baz:0'
      expect { artifact_ns.ns(:foo) }.to raise_error(TypeError, /not a sub/i)
    end

    it 'should clone artifacts when assigned' do
      artifact_ns(:foo).bar = "foo:bar:jar:0"
      artifact_ns(:moo).ns :muu, :miu => artifact_ns(:foo).bar
      expect(artifact_ns(:moo).muu.miu).not_to eq(artifact_ns(:foo).bar)
      expect(artifact_ns(:moo).muu.miu.to_spec).to eq(artifact_ns(:foo).bar.to_spec)
    end

    it 'should clone parent artifacts by name' do
      define 'foo' do
        artifact_ns.bar = "foo:bar:jar:0"
        define 'moo' do
          artifact_ns.ns(:muu).use :bar
          expect(artifact_ns.muu_bar).to be_selected
          expect(artifact_ns.muu.bar).not_to eq(artifact_ns.bar)
        end
      end
    end
  end

  it 'should be an Enumerable' do
    expect(artifact_ns).to be_kind_of(Enumerable)
    artifact_ns.use 'foo:bar:baz:1.0'
    expect(artifact_ns.map(&:artifact)).to include(artifact('foo:bar:baz:1.0'))
  end

end # ArtifactNamespace

describe Buildr::ArtifactNamespace::ArtifactRequirement do
  before(:each) { Buildr::ArtifactNamespace.clear }
  it 'should be created from artifact_ns' do
    foo = artifact_ns do |ns|
      ns.bar = 'a:b:c:1.0'
    end
    expect(foo.bar).to be_kind_of(ArtifactNamespace::ArtifactRequirement)
  end

  it 'should handle version as string' do
    foo = artifact_ns do |ns|
      ns.bar = 'a:b:c:1.0'
    end
    foo.bar.version = '2.0'
    expect(foo.bar.version).to eq('2.0')
  end

  it 'should handle version string directly' do
    foo = artifact_ns do |ns|
      ns.bar = 'a:b:c:1.0'
    end
    foo.bar = '2.0'
    expect(foo.bar.version).to eq('2.0')
  end

end # ArtifactRequirement

describe Buildr do
  before(:each) { Buildr::ArtifactNamespace.clear }

  describe '.artifacts' do
    it 'should take ruby symbols and ask the current namespace for them' do
      define 'foo' do
        artifact_ns.cool = 'cool:aid:jar:1.0'
        artifact_ns.use 'some:other:jar:1.0'
        artifact_ns.use 'bat:man:jar:1.0'
        compile.with :cool, :other, :'bat:man:jar'
        expect(compile.dependencies.map(&:to_spec)).to include('cool:aid:jar:1.0', 'some:other:jar:1.0', 'bat:man:jar:1.0')
      end
    end

    it 'should take a namespace' do
      artifact_ns(:moo).muu = 'moo:muu:jar:1.0'
      define 'foo' do
        compile.with artifact_ns(:moo)
        expect(compile.dependencies.map(&:to_spec)).to include('moo:muu:jar:1.0')
      end
    end
  end

  describe '.artifact' do
    it 'should search current namespace if given a symbol' do
      define 'foo' do
        artifact_ns.use :cool => 'cool:aid:jar:1.0'
        define 'bar' do
          expect(artifact(:cool)).to eq(artifact_ns[:cool].artifact)
        end
      end
    end

    it 'should search current namespace if given a symbol spec' do
      define 'foo' do
        artifact_ns.use 'cool:aid:jar:1.0'
        define 'bar' do
          expect(artifact(:'cool:aid:jar')).to eq(artifact_ns[:aid].artifact)
        end
      end
    end

    it 'should fail when no artifact by that name is found' do
      define 'foo' do
        artifact_ns.use 'cool:aid:jar:1.0'
        define 'bar' do
          expect { artifact(:cool) }.to raise_error(IndexError, /artifact/)
        end
      end
    end
  end
end

describe "Extension using ArtifactNamespace" do
  before(:each) { Buildr::ArtifactNamespace.clear }

  def abc_module
    Object.module_eval 'module A; module B; module C; end; end; end'
    yield
  ensure
    Object.send :remove_const, :A
  end

  it 'can register namespace listeners' do
    abc_module do
      # An example extension to illustrate namespace listeners and method forwarding
      class A::Example

        module Ext
          include Buildr::Extension
          def example; @example ||= A::Example.new; end
          before_define do |p|
            Rake::Task.define_task('example') { p.example.doit }
          end
        end

        REQUIRES = ArtifactNamespace.for(self) do |ns|
          ns.xmlbeans! 'org.apache.xmlbeans:xmlbeans:jar:2.3.0', '>2'
          ns.stax_api! 'stax:stax-api:jar:>=1.0.1'
        end

        attr_reader :options, :requires

        def initialize
          # We could actually use the REQUIRES namespace, but to make things
          # a bit more interesting, suppose each Example instance can have its
          # own artifact requirements in adition to those specified on REQUIRES.
          # To achieve this we create an anonymous namespace.
          @requires = ArtifactNamespace.new # a namespace per instance
          REQUIRES.each { |requirement| @requires.need requirement }

          # For user convenience, we make the options object respond to
          #    :xmlbeans, :xmlbeans=, :xmlbeans?
          # forwarding them to the namespace.
          @options = OpenObject.new.extend(@requires.accessor(:xmlbeans, :stax_api))
          # Register callbacks so we can perform some logic when an artifact
          # is selected by the user.
          options.xmlbeans.add_listener &method(:selected_xmlbeans)
          options.stax_api.add_listener do |stax|
            # Now using a proc
            expect(stax).to be_selected
            expect(stax.version).to eq('1.6180')
            options[:math] = :golden # customize our options for this version
            # In this example we set the stax version when running outside
            # a project definition. This means we have no access to the project
            # namespace unless we had a reference to the project or knew it's name
            expect(Buildr.artifact_ns(:current).name).to eq('root')
          end
        end

        include RSpec::Matchers # for assertions

        # Called with the ArtifactRequirement that has just been selected
        # by a user. This allows extension author to selectively perform
        # some action by inspecting the requirement state.
        def selected_xmlbeans(xmlbeans)
          expect(xmlbeans).to be_selected
          expect(xmlbeans.version).to eq('3.1415')
          options[:math] = :pi
          # This example just sets xmlbeans for foo:bar project
          # So the currently running namespace should have the foo:bar name
          expect(Buildr.artifact_ns(:current).name).to eq('foo:bar')
        end

        # Suppose we invoke an ant task here or something else.
        def doit
          # Now call ant task with our selected artifact and options
          classpath = requires.map(&:artifact).map(&:to_s).join(File::PATH_SEPARATOR)
          lambda { ant('thing') { |ant| ant.classpath classpath, :math => options[:math] } }

          # We are not a Project instance, hence we have no artifact_ns
          expect { artifact_ns }.to raise_error(NameError)

          # Extension authors may NOT rely project's namespaces.
          # However the ruby-way gives you power and at the same time
          # makes you dangerous, (think open-modules, monkey-patching)
          # Given that buildr is pure ruby, consider it a sharp-edged sword.
          # Having said that, you may actually inspect a project's
          # namespace, but don't write on it without letting your users
          # know you will.
          # This example obtains the current project namespace to make
          # some assertions.

          # To obtain a project's namespace we need either
          # 1) a reference to the project, and call artifact_ns on it
          #      project.artifact_ns  # the namespace for project
          # 2) know the project name
          #      Buildr.artifact_ns('the:project')
          # 3) Use :current to reference the currently running project
          #      Buildr.artifact_ns(:current)
          name = Buildr.artifact_ns(:current).name
          case name
          when 'foo:bar'
            expect(options[:math]).to eq(:pi)
            expect(requires.xmlbeans.version).to eq('3.1415')
            expect(requires.stax_api.version).to eq('1.0.1')
          when 'foo:baz'
            expect(options[:math]).to eq(:golden)
            expect(requires.xmlbeans.version).to eq('2.3.0')
            expect(requires.stax_api.version).to eq('1.6180')
          else
            fail "This example expects foo:bar or foo:baz projects not #{name.inspect}"
          end
        end
      end

      define 'foo' do
        define 'bar' do
          extend A::Example::Ext
          task('setup') do
            example.options.xmlbeans = '3.1415'
          end
          task('run' => [:setup, :example])
        end
        define 'baz' do
          extend A::Example::Ext
        end
      end

      expect(project('foo:bar').example.requires).not_to eq(project('foo:baz').example.requires)
      expect(project('foo:bar').example.requires.xmlbeans).not_to eq(project('foo:baz').example.requires.xmlbeans)

      # current namespace outside a project is :root, see the stax callback
      project('foo:baz').example.options.stax_api = '1.6180'
      # we call the task outside the project, see #doit
      expect { task('foo:bar:run').invoke }.to run_task('foo:bar:example')
      expect { task('foo:baz:example').invoke }.to run_task('foo:baz:example')
    end
  end
end
