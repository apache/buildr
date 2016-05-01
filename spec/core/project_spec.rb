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


describe Project do
  it 'should be findable' do
    foo = define('foo')
    expect(project('foo')).to be(foo)
  end

  it 'should not exist unless defined' do
    expect { project('foo') }.to raise_error(RuntimeError, /No such project/)
  end

  it 'should fail to be defined if its name is already used for a task' do
    expect { define('test') }.to raise_error(RuntimeError, /Invalid project name/i)
    define 'valid' do
      expect { define('build') }.to raise_error(RuntimeError, /Invalid project name/i)
    end
  end

  it 'should exist once defined' do
    define 'foo'
    expect { project('foo') }.not_to raise_error
  end

  it 'should always return same project for same name' do
    foo, bar = define('foo'), define('bar')
    expect(foo).not_to be(bar)
    expect(foo).to be(project('foo'))
    expect(bar).to be(project('bar'))
  end

  it 'should show up in projects list if defined' do
    define('foo')
    expect(projects.map(&:name)).to include('foo')
  end

  it 'should not show up in projects list unless defined' do
    expect(projects.map(&:name)).not_to include('foo')
  end

  it 'should be findable from within a project' do
    define('foo')
    expect(project('foo').project('foo')).to be(project('foo'))
  end

  it 'should cease to exist when project list cleared' do
    define 'foo'
    expect(projects.map(&:name)).to include('foo')
    Project.clear
    expect(projects.map(&:name)).to be_empty
  end

  it 'should be defined only once' do
    expect { define 'foo' }.not_to raise_error
    expect { define 'foo' }.to raise_error /You cannot define the same project/
  end

  it 'should be definable in any order' do
    Buildr.define('baz') { define('bar') { project('foo:bar') } }
    Buildr.define('foo') { define('bar') }
    expect { project('foo') }.not_to raise_error
  end

  it 'should detect circular dependency' do
    Buildr.define('baz') { define('bar') { project('foo:bar') } }
    Buildr.define('foo') { define('bar') { project('baz:bar') } }
    expect { project('foo') }.to raise_error(RuntimeError, /Circular dependency/)
  end
end

describe Project, ' property' do
  it 'should be set if passed as argument' do
    define 'foo', 'version'=>'1.1'
    expect(project('foo').version).to eql('1.1')
  end

  it 'should be set if assigned in body' do
    define('foo') { self.version = '1.2' }
    expect(project('foo').version).to eql('1.2')
  end

  it 'should take precedence when assigned in body' do
    define('foo', 'version'=>'1.1') { self.version = '1.2' }
    expect(project('foo').version).to eql('1.2')
  end

  it 'should inherit from parent (for some properties)' do
    define('foo', 'version'=>'1.2', :group=>'foobar') { define 'bar' }
    expect(project('foo:bar').version).to eql('1.2')
    expect(project('foo:bar').group).to eql('foobar')
  end

  it 'should have different value if set in sub-project' do
    define 'foo', 'version'=>'1.2', :group=>'foobar' do
      define 'bar', :version=>'1.3' do
        self.group = 'barbaz'
      end
    end
    expect(project('foo:bar').version).to eql('1.3')
    expect(project('foo:bar').group).to eql('barbaz')
  end
end


describe Project, ' block' do
  it 'should execute once' do
    define('foo') { expect(self.name).to eql('foo') }
  end

  it 'should execute in describe of project' do
    define('foo') { self.version = '1.3' }
    expect(project('foo').version).to eql('1.3')
  end

  it 'should execute by passing project' do
    define('foo') { |project| project.version = '1.3' }
    expect(project('foo').version).to eql('1.3')
  end

  it 'should execute in namespace of project' do
    define('foo') { define('bar') { expect(Buildr.application.current_scope).to eql(['foo', 'bar']) } }
  end
end


describe Project, '#base_dir' do
  it 'should be pwd if not specified' do
    expect(define('foo').base_dir).to eql(Dir.pwd)
  end

  it 'should come from property, if specified' do
    foo = define('foo', :base_dir=>'tmp')
    expect(foo.base_dir).to point_to_path('tmp')
  end

  it 'should be expanded path' do
    foo = define('foo', :base_dir=>'tmp')
    expect(foo.base_dir).to eql(File.expand_path('tmp'))
  end

  it 'should be relative to parent project' do
    define('foo') { define('bar') { define 'baz' } }
    expect(project('foo:bar:baz').base_dir).to point_to_path('bar/baz')
  end

  it 'should be settable only if not read' do
    expect { define('foo', :base_dir=>'tmp') }.not_to raise_error
    expect { define('bar', :base_dir=>'tmp') { self.base_dir = 'bar' } }.to raise_error(Exception, /Cannot set/)
  end
end


describe Layout do
  before :each do
    @layout = Layout.new
  end

  it 'should expand empty to itself' do
    expect(@layout.expand).to eql('')
    expect(@layout.expand('')).to eql('')
  end

  it 'should expand array of symbols' do
    expect(@layout.expand(:foo, :bar)).to eql('foo/bar')
  end

  it 'should expand array of names' do
    expect(@layout.expand('foo', 'bar')).to eql('foo/bar')
  end

  it 'should map symbol to path' do
    @layout[:foo] = 'baz'
    expect(@layout.expand(:foo, :bar)).to eql('baz/bar')
  end

  it 'should map symbols to path' do
    @layout[:foo, :bar] = 'none'
    expect(@layout.expand(:foo, :bar)).to eql('none')
  end

  it 'should map strings to path' do
    @layout[:foo, "bar"] = 'none'
    expect(@layout.expand(:foo, :bar)).to eql('none')
    expect(@layout.expand(:foo, 'bar')).to eql('none')
  end

  it 'should ignore nil elements' do
    @layout[:foo, :bar] = 'none'
    expect(@layout.expand(:foo, nil, :bar)).to eql('none')
    expect(@layout.expand(nil, :foo)).to eql('foo')
  end

  it 'should return nil if path not mapped' do
    expect(@layout[:foo]).to be_nil
  end

  it 'should return path from symbol' do
    @layout[:foo] = 'path'
    expect(@layout[:foo]).to eql('path')
  end

  it 'should return path from symbol' do
    @layout[:foo, :bar] = 'path'
    expect(@layout[:foo, :bar]).to eql('path')
  end

  it 'should do eager mapping' do
    @layout[:one] = 'none'
    @layout[:one, :two] = '1..2'
    expect(@layout.expand(:one, :two, :three)).to eql('1..2/three')
  end

end


describe Project, '#layout' do
  before :each do
    @layout = Layout.new
  end

  it 'should exist by default' do
    expect(define('foo').layout).to respond_to(:expand)
  end

  it 'should be clone of default layout' do
    define 'foo' do
      expect(layout).not_to be(Layout.default)
      expect(layout.expand(:test, :main)).to eql(Layout.default.expand(:test, :main))
    end
  end

  it 'should come from property, if specified' do
    foo = define('foo', :layout=>@layout)
    expect(foo.layout).to eql(@layout)
  end

  it 'should inherit from parent project' do
    define 'foo', :layout=>@layout do
      layout[:foo] = 'foo'
      define 'bar'
    end
    expect(project('foo:bar').layout[:foo]).to eql('foo')
  end

  it 'should clone when inheriting from parent project' do
    define 'foo', :layout=>@layout do
      layout[:foo] = 'foo'
      define 'bar' do
        layout[:foo] = 'bar'
      end
    end
    expect(project('foo').layout[:foo]).to eql('foo')
    expect(project('foo:bar').layout[:foo]).to eql('bar')
  end

  it 'should be settable only if not read' do
    expect { define('foo', :layout=>@layout) }.not_to raise_error
    expect { define('bar', :layout=>@layout) { self.layout = @layout.clone } }.to raise_error(Exception, /Cannot set/)
  end

end


describe Project, '#path_to' do
  it 'should return absolute paths as is' do
    expect(define('foo').path_to('/tmp')).to eql(File.expand_path('/tmp'))
  end

  it 'should resolve empty path to project\'s base directory' do
    expect(define('foo').path_to).to eql(project('foo').base_dir)
  end

  it 'should resolve relative paths' do
    expect(define('foo').path_to('tmp')).to eql(File.expand_path('tmp'))
  end

  it 'should accept multiple arguments' do
    expect(define('foo').path_to('foo', 'bar')).to eql(File.expand_path('foo/bar'))
  end

  it 'should handle relative paths' do
    expect(define('foo').path_to('..', 'bar')).to eql(File.expand_path('../bar'))
  end

  it 'should resolve symbols using layout' do
    define('foo').layout[:foo] = 'bar'
    expect(project('foo').path_to(:foo)).to eql(File.expand_path('bar'))
    expect(project('foo').path_to(:foo, 'tmp')).to eql(File.expand_path('bar/tmp'))
  end

  it 'should resolve path for sub-project' do
    define('foo') { define 'bar' }
    expect(project('foo:bar').path_to('foo')).to eql(File.expand_path('foo', project('foo:bar').base_dir))
  end

  it 'should be idempotent for relative paths' do
    define 'foo'
    path = project('foo').path_to('bar')
    expect(project('foo').path_to(path)).to eql(path)
  end
end


describe Project, '#on_define' do
  it 'should be called when project is defined' do
    names = []
    Project.on_define { |project| names << project.name }
    define 'foo' ; define 'bar'
    expect(names).to eql(['foo', 'bar'])
  end

  it 'should be called with project object' do
    Project.on_define { |project| expect(project.name).to eql('foo') }
    define('foo')
  end

  it 'should be called with project object and set properties' do
    Project.on_define { |project| expect(project.version).to eql('2.0') }
    define('foo', :version=>'2.0')
  end

  it 'should execute in namespace of project' do
    scopes = []
    Project.on_define { |project| scopes << Buildr.application.current_scope }
    define('foo') { define 'bar' }
    expect(scopes).to eql([['foo'], ['foo', 'bar']])
  end

  it 'should be called before project block' do
    order = []
    Project.on_define { |project| order << 'on_define' }
    define('foo') { order << 'define' }
    expect(order).to eql(['on_define', 'define'])
  end

  it 'should accept enhancement and call it after project block' do
    order = []
    Project.on_define { |project| project.enhance { order << 'enhance' } }
    define('foo') { order << 'define' }
    expect(order).to eql(['define', 'enhance'])
  end

  it 'should accept enhancement and call it with project' do
    Project.on_define { |project| project.enhance { |project| expect(project.name).to eql('foo') } }
    define('foo')
  end

  it 'should execute enhancement in namespace of project' do
    scopes = []
    Project.on_define { |project| project.enhance { scopes << Buildr.application.current_scope } }
    define('foo') { define 'bar' }
    expect(scopes).to eql([['foo'], ['foo', 'bar']])
  end

  it 'should be removed in version 1.5 since it was deprecated in version 1.3' do
    expect(Buildr::VERSION).to be < '1.5'
  end
end


describe Rake::Task, ' recursive' do
  before do
    @order = []
    Project.on_define do |project| # TODO on_define is deprecated
      project.recursive_task('doda') { @order << project.name }
    end
    define('foo') { define('bar') { define('baz') } }
  end

  it 'should invoke same task in child project' do
    task('foo:doda').invoke
    expect(@order).to include('foo:bar:baz')
    expect(@order).to include('foo:bar')
    expect(@order).to include('foo')
  end

  it 'should invoke in depth-first order' do
    task('foo:doda').invoke
    expect(@order).to eql([ 'foo:bar:baz', 'foo:bar', 'foo' ])
  end

  it 'should not invoke task in parent project' do
    task('foo:bar:baz:doda').invoke
    expect(@order).to eql([ 'foo:bar:baz' ])
  end
end


describe 'Sub-project' do
  it 'should point at parent project' do
    define('foo') { define 'bar' }
    expect(project('foo:bar').parent).to be(project('foo'))
  end

  it 'should be defined only within parent project' do
    expect { define('foo:bar') }.to raise_error /You can only define a sub project .* within the definition of its parent project/
  end

  it 'should have unique name' do
    expect do
      define 'foo' do
        define 'bar'
        define 'bar'
      end
    end.to raise_error /You cannot define the same project/
  end

  it 'should be findable from root' do
    define('foo') { define 'bar' }
    expect(projects.map(&:name)).to include('foo:bar')
  end

  it 'should be findable from parent project' do
    define('foo') { define 'bar' }
    expect(project('foo').projects.map(&:name)).to include('foo:bar')
  end

  it 'should be findable during project definition' do
    define 'foo' do
      bar = define 'bar' do
        baz = define 'baz'
        expect(project('baz')).to eql(baz)
      end
      # Note: evaluating bar:baz first unearthed a bug that doesn't happen
      # if we evaluate bar, then bar:baz.
      expect(project('bar:baz')).to be(bar.project('baz'))
      expect(project('bar')).to be(bar)
    end
  end

  it 'should be findable only if exists' do
    define('foo') { define 'bar' }
    expect { project('foo').project('baz') }.to raise_error(RuntimeError, /No such project/)
  end

  it 'should always execute its definition ' do
    ordered = []
    define 'foo' do
      ordered << self.name
      define('bar') { ordered << self.name }
      define('baz') { ordered << self.name }
    end
    expect(ordered).to eql(['foo', 'foo:bar', 'foo:baz'])
  end

  it 'should execute in order of dependency' do
    ordered = []
    define 'foo' do
      ordered << self.name
      define('bar') { project('foo:baz') ; ordered << self.name }
      define('baz') { ordered << self.name }
    end
    expect(ordered).to eql(['foo', 'foo:baz', 'foo:bar'])
  end

  it 'should warn of circular dependency' do
    expect do
      define 'foo' do
        define('bar') { project('foo:baz') }
        define('baz') { project('foo:bar') }
      end
    end.to raise_error(RuntimeError, /Circular dependency/)
  end
end


describe 'Top-level project' do
  it 'should have no parent' do
    define('foo')
    expect(project('foo').parent).to be_nil
  end
end


describe Buildr, '#project' do
  it 'should raise error if no such project' do
    expect { project('foo') }.to raise_error(RuntimeError, /No such project/)
  end

  it 'should return a project if exists' do
    foo = define('foo')
    expect(project('foo')).to be(foo)
  end

  it 'should define a project if a block is given' do
    foo = project('foo') {}
    expect(project('foo')).to be(foo)
  end

  it 'should define a project if properties and a block are given' do
    foo = project('foo', :version => '1.2') {}
    expect(project('foo')).to be(foo)
  end

  it 'should find a project by its full name' do
    bar, baz = nil
    define('foo') { bar = define('bar') { baz = define('baz')  } }
    expect(project('foo:bar')).to be(bar)
    expect(project('foo:bar:baz')).to be(baz)
  end

  it 'should find a project from any context' do
    bar, baz = nil
    define('foo') { bar = define('bar') { baz = define('baz')  } }
    expect(project('foo:bar').project('foo:bar:baz')).to be(baz)
    expect(project('foo:bar:baz').project('foo:bar')).to be(bar)
  end

  it 'should find a project from its parent or sibling project' do
    define 'foo' do
      define 'bar'
      define 'baz'
    end
    expect(project('foo').project('bar')).to be(project('foo:bar'))
    expect(project('foo').project('baz')).to be(project('foo:baz'))
    expect(project('foo:bar').project('baz')).to be(project('foo:baz'))
  end

  it 'should fine a project from its parent by proximity' do
    define 'foo' do
      define('bar') { define 'baz' }
      define 'baz'
    end
    expect(project('foo').project('baz')).to be(project('foo:baz'))
    expect(project('foo:bar').project('baz')).to be(project('foo:bar:baz'))
  end

  it 'should invoke project before returning it' do
    expect(define('foo')).to receive(:invoke).once
    project('foo')
  end

  it 'should fail if called without a project name' do
    expect { project }.to raise_error(ArgumentError)
  end

  it 'should return self if called on a project without a name' do
    define('foo') { expect(project).to be(self) }
  end

  it 'should evaluate parent project before returning' do
    # Note: gets around our define that also invokes the project.
    Buildr.define('foo') { define('bar'); define('baz') }
    expect(project('foo:bar')).to eql(projects[1])
  end
end


describe Buildr, '#projects' do
  it 'should only return defined projects' do
    expect(projects).to eql([])
    define 'foo'
    expect(projects).to eql([project('foo')])
  end

  it 'should return all defined projects' do
    define 'foo'
    define('bar') { define 'baz' }
    expect(projects).to include(project('foo'))
    expect(projects).to include(project('bar'))
    expect(projects).to include(project('bar:baz'))
  end

  it 'should return only named projects' do
    define 'foo' ; define 'bar' ; define 'baz'
    expect(projects('foo', 'bar')).to include(project('foo'))
    expect(projects('foo', 'bar')).to include(project('bar'))
    expect(projects('foo', 'bar')).not_to include(project('baz'))
  end

  it 'should complain if named project does not exist' do
    define 'foo'
    expect(projects('foo')).to include(project('foo'))
    expect { projects('bar') }.to raise_error(RuntimeError, /No such project/)
  end

  it 'should find a project from its parent or sibling project' do
    define 'foo' do
      define 'bar'
      define 'baz'
    end
    expect(project('foo').projects('bar')).to eql(projects('foo:bar'))
    expect(project('foo').projects('baz')).to eql(projects('foo:baz'))
    expect(project('foo:bar').projects('baz')).to eql(projects('foo:baz'))
  end

  it 'should fine a project from its parent by proximity' do
    define 'foo' do
      define('bar') { define 'baz' }
      define 'baz'
    end
    expect(project('foo').projects('baz')).to eql(projects('foo:baz'))
    expect(project('foo:bar').projects('baz')).to eql(projects('foo:bar:baz'))
  end

  it 'should evaluate all projects before returning' do
    # Note: gets around our define that also invokes the project.
    Buildr.define('foo') { define('bar'); define('baz') }
    expect(projects).to eql(projects('foo', 'foo:bar', 'foo:baz'))
  end
end


describe Rake::Task, ' local directory' do
  before do
    @task = Project.local_task(task(('doda')))
    Project.on_define { |project| task('doda') { |task| @task.from project.name } }
  end

  it 'should execute project in local directory' do
    define 'foo'
    expect(@task).to receive(:from).with('foo')
    @task.invoke
  end

  it 'should execute sub-project in local directory' do
    expect(@task).to receive(:from).with('foo:bar')
    define('foo') { define 'bar' }
    in_original_dir(project('foo:bar').base_dir) { @task.invoke }
  end

  it 'should do nothing if no project in local directory' do
    expect(@task).not_to receive(:from)
    define('foo') { define 'bar' }
    in_original_dir('../not_foo') { @task.invoke }
  end

  it 'should find closest project that matches current directory' do
    mkpath 'bar/src/main'
    define('foo') { define 'bar' }
    expect(@task).to receive(:from).with('foo:bar')
    in_original_dir('bar/src/main') { @task.invoke }
  end
end


describe Project, '#task' do
  it 'should create a regular task' do
    define('foo') { task('bar') }
    expect(Buildr.application.lookup('foo:bar')).not_to be_nil
  end

  it 'should return a task defined in the project' do
    define('foo') { task('bar') }
    expect(project('foo').task('bar')).to be_instance_of(Rake::Task)
  end

  it 'should not create task outside project definition' do
    define 'foo'
    expect { project('foo').task('bar') }.to raise_error(RuntimeError, /no task foo:bar/)
  end

  it 'should include project name as prefix' do
    define('foo') { task('bar') }
    expect(project('foo').task('bar').name).to eql('foo:bar')
  end

  it 'should ignore namespace if starting with colon' do
    define 'foo' do
      expect(task(':bar').name).to eq('bar')
    end
    expect(Rake::Task.task_defined?('bar')).to be_truthy
  end

  it 'should accept single dependency' do
    define('foo') { task('bar'=>'baz') }
    expect(project('foo').task('bar').prerequisites).to include('baz')
  end

  it 'should accept multiple dependencies' do
    define('foo') { task('bar'=>['baz1', 'baz2']) }
    expect(project('foo').task('bar').prerequisites).to include('baz1')
    expect(project('foo').task('bar').prerequisites).to include('baz2')
  end

  it 'should execute task exactly once' do
    define('foo') do
      task 'baz'
      task 'bar'=>'baz'
    end
    expect { project('foo').task('bar').invoke }.to run_tasks(['foo:baz', 'foo:bar'])
  end

  it 'should create a file task' do
    define('foo') { file('bar') }
    expect(Buildr.application.lookup(File.expand_path('bar'))).not_to be_nil
  end

  it 'should create file task with absolute path' do
    define('foo') { file('/tmp') }
    expect(Buildr.application.lookup(File.expand_path('/tmp'))).not_to be_nil
  end

  it 'should create file task relative to project base directory' do
    define('foo', :base_dir=>'tmp') { file('bar') }
    expect(Buildr.application.lookup(File.expand_path('tmp/bar'))).not_to be_nil
  end

  it 'should accept single dependency' do
    define('foo') { file('bar'=>'baz') }
    expect(project('foo').file('bar').prerequisites).to include('baz')
  end

  it 'should accept multiple dependencies' do
    define('foo') { file('bar'=>['baz1', 'baz2']) }
    expect(project('foo').file('bar').prerequisites).to include('baz1')
    expect(project('foo').file('bar').prerequisites).to include('baz2')
  end

  it 'should accept hash arguments' do
    define('foo') do
      task 'bar'=>'bar_dep'
      file 'baz'=>'baz_dep'
    end
    expect(project('foo').task('bar').prerequisites).to include('bar_dep')
    expect(project('foo').file('baz').prerequisites).to include('baz_dep')
  end

  it 'should return a file task defined in the project' do
    define('foo') { file('bar') }
    expect(project('foo').file('bar')).to be_instance_of(Rake::FileTask)
  end

  it 'should create file task relative to project definition' do
    define('foo') { define 'bar' }
    expect(project('foo:bar').file('baz').name).to point_to_path('bar/baz')
  end

  it 'should execute task exactly once' do
    define('foo') do
      task 'baz'
      file 'bar'=>'baz'
    end
    expect { project('foo').file('bar').invoke }.to run_tasks(['foo:baz', project('foo').path_to('bar')])
  end
end


=begin
describe Buildr::Generate do
  it 'should be able to create buildfile from directory structure' do
    write 'src/main/java/Foo.java', ''
    write 'one/two/src/main/java/Foo.java', ''
    write 'one/three/src/main/java/Foo.java', ''
    write 'four/src/main/java/Foo.java', ''
    script = Buildr::Generate.from_directory(Dir.pwd)
    instance_eval(script.join("\n"), "generated buildfile")
    # projects should have been defined
    root = Dir.pwd.pathmap('%n')
    names = [root, "#{root}:one:two", "#{root}:one:three", "#{root}:four"]
    # the top level project has the directory name.
    names.each { |name| lambda { project(name) }.should_not raise_error }
  end
end
=end
