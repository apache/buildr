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


describe Project, 'check task' do

  it "should execute last thing from package task" do
    task 'action'
    define 'foo', :version=>'1.0' do
      package :jar
      task('package').enhance { task('action').invoke }
    end
    expect { project('foo').task('package').invoke }.to run_tasks(['foo:package', 'action', 'foo:check'])
  end

  it "should execute all project's expectations" do
    task 'expectation'
    define 'foo', :version=>'1.0' do
      check  { task('expectation').invoke }
    end
    expect { project('foo').task('package').invoke }.to run_task('expectation')
  end

  it "should succeed if there are no expectations" do
    define 'foo', :version=>'1.0'
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should succeed if all expectations passed" do
    define 'foo', :version=>'1.0' do
      check { true }
      check { false }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should fail if any expectation failed" do
    define 'foo', :version=>'1.0' do
      check
      check { fail 'sorry' }
      check
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end
end


describe Project, '#check' do

  it "should add expectation" do
    define 'foo' do
      expect(expectations).to be_empty
      check
      expect(expectations.size).to be(1)
    end
  end

  it "should treat no arguments as expectation against project" do
    define 'foo' do
      subject = self
      check do
        expect(it).to be(subject)
        expect(description).to eql(subject.to_s)
      end
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should treat single string argument as description, expectation against project" do
    define 'foo' do
      subject = self
      check "should be project" do
        expect(it).to be(subject)
        expect(description).to eql("#{subject} should be project")
      end
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should treat single object argument as subject" do
    define 'foo' do
      subject = Object.new
      check subject do
        expect(it).to be(subject)
        expect(description).to eql(subject.to_s)
      end
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should treat first object as subject, second object as description" do
    define 'foo' do
      subject = Object.new
      check subject, "should exist" do
        expect(it).to be(subject)
        expect(description).to eql("#{subject} should exist")
      end
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should work without block" do
    define 'foo' do
      check "implement later"
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it 'should pass method calls to context' do
    define 'foo', :version=>'1.0' do
      subject = self
      check "should be project" do
        expect(it).to be(subject)
        expect(name).to eql(subject.name)
        expect(package(:jar)).to eql(subject.package(:jar))
      end
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end
end


describe Buildr::Checks::Expectation, 'matchers' do

  it "should include Buildr matchers exist and contain" do
    define 'foo' do
      check do
        expect(self).to respond_to(:exist)
        expect(self).to respond_to(:contain)
      end
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should include RSpec matchers like be and eql" do
    define 'foo' do
      check do
        expect(self).to respond_to(:be)
        expect(self).to respond_to(:eql)
      end
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should include RSpec predicates like be_nil and be_empty" do
    define 'foo' do
      check do
        expect(nil).to be_nil
        expect([]).to be_empty
      end
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end
end


describe Buildr::Checks::Expectation, 'exist' do

  it "should pass if file exists" do
    define 'foo' do
      build file('test') { |task| write task.name }
      check(file('test')) { expect(it).to exist }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should fail if file does not exist" do
    define 'foo' do
      check(file('test')) { expect(it).to exist }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end

  it "should not attempt to invoke task" do
    define 'foo' do
      file('test') { |task| write task.name }
      check(file('test')) { expect(it).to exist }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end
end


describe Buildr::Checks::Expectation, " be_empty" do

  it "should pass if file has no content" do
    define 'foo' do
      build file('test') { write 'test' }
      check(file('test')) { expect(it).to be_empty }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should fail if file has content" do
    define 'foo' do
      build file('test') { write 'test', "something" }
      check(file('test')) { expect(it).to be_empty }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end

  it "should fail if file does not exist" do
    define 'foo' do
      check(file('test')) { expect(it).to be_empty }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end

  it "should pass if directory is empty" do
    define 'foo' do
      build file('test') { mkpath 'test' }
      check(file('test')) { expect(it).to be_empty }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should fail if directory has any files" do
    define 'foo' do
      build file('test') { write 'test/file' }
      check(file('test')) { expect(it).to be_empty }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end
end


describe Buildr::Checks::Expectation, " contain(file)" do

  it "should pass if file content matches string" do
    define 'foo' do
      build file('test') { write 'test', 'something' }
      check(file('test')) { expect(it).to contain('thing') }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should pass if file content matches pattern" do
    define 'foo' do
      build file('test') { write 'test', "something\nor\nanother" }
      check(file('test')) { expect(it).to contain(/or/) }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should pass if file content matches all arguments" do
    define 'foo' do
      build file('test') { write 'test', "something\nor\nanother" }
      check(file('test')) { expect(it).to contain(/or/, /other/) }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should fail unless file content matchs all arguments" do
    define 'foo' do
      build file('test') { write 'test', 'something' }
      check(file('test')) { expect(it).to contain(/some/, /other/) }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end

  it "should fail if file content does not match" do
    define 'foo' do
      build file('test') { write 'test', "something" }
      check(file('test')) { expect(it).to contain(/other/) }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end

  it "should fail if file does not exist" do
    define 'foo' do
      check(file('test')) { expect(it).to contain(/anything/) }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end
end


describe Buildr::Checks::Expectation, 'contain(directory)' do

  it "should pass if directory contains file" do
    write 'resources/test'
    define 'foo' do
      check(file('resources')) { expect(it).to contain('test') }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should pass if directory contains glob pattern" do
    write 'resources/with/test'
    define 'foo' do
      check(file('resources')) { expect(it).to contain('**/t*st') }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should pass if directory contains all arguments" do
    write 'resources/with/test'
    define 'foo' do
      check(file('resources')) { expect(it).to contain('**/test', '**/*') }
    end
    expect { project('foo').task('package').invoke }.not_to raise_error
  end

  it "should fail unless directory contains all arguments" do
    write 'resources/test'
    define 'foo' do
      check(file('resources')) { expect(it).to contain('test', 'or-not') }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end

  it "should fail if directory is empty" do
    mkpath 'resources'
    define 'foo' do
      check(file('resources')) { expect(it).to contain('test') }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end

  it "should fail if directory does not exist" do
    define 'foo' do
      check(file('resources')) { expect(it).to contain }
    end
    expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
  end
end


describe Buildr::Checks::Expectation do

  shared_examples_for 'all archive types' do

    before do
      archive = @archive
      define 'foo', :version=>'1.0' do
        package(archive).include('resources')
      end
    end

    def check *args, &block
      project('foo').check *args, &block
    end

    def package
      project('foo').package(@archive)
    end

    describe '#exist' do

      it "should pass if archive path exists" do
        write 'resources/test'
        check(package.path('resources')) { expect(it).to exist }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should fail if archive path does not exist" do
        mkpath 'resources'
        check(package) { expect(it.path('not-resources')).to exist }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end

      it "should pass if archive entry exists" do
        write 'resources/test'
        check(package.entry('resources/test')) { expect(it).to exist }
        check(package.path('resources').entry('test')) { expect(it).to exist }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should fail if archive path does not exist" do
        mkpath 'resources'
        check(package.entry('resources/test')) { expect(it).to exist }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end
    end

    describe '#be_empty' do
      it "should pass if archive path is empty" do
        mkpath 'resources'
        check(package.path('resources')) { expect(it).to be_empty }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should fail if archive path has any entries" do
        write 'resources/test'
        check(package.path('resources')) { expect(it).to be_empty }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end

      it "should pass if archive entry has no content" do
        write 'resources/test'
        check(package.entry('resources/test')) { expect(it).to be_empty }
        check(package.path('resources').entry('test')) { expect(it).to be_empty }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should fail if archive entry has content" do
        write 'resources/test', 'something'
        check(package.entry('resources/test')) { expect(it).to be_empty }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end

      it "should fail if archive entry does not exist" do
        mkpath 'resources'
        check(package.entry('resources/test')) { expect(it).to be_empty }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end
    end

    describe '#contain(entry)' do

      it "should pass if archive entry content matches string" do
        write 'resources/test', 'something'
        check(package.entry('resources/test')) { expect(it).to contain('thing') }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should pass if archive entry content matches pattern" do
        write 'resources/test', "something\nor\another"
        check(package.entry('resources/test')) { expect(it).to contain(/or/) }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should pass if archive entry content matches all arguments" do
        write 'resources/test', "something\nor\nanother"
        check(package.entry('resources/test')) { expect(it).to contain(/or/, /other/) }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should fail unless archive path contains all arguments" do
        write 'resources/test', 'something'
        check(package.entry('resources/test')) { expect(it).to contain(/some/, /other/) }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end

      it "should fail if archive entry content does not match" do
        write 'resources/test', 'something'
        check(package.entry('resources/test')) { expect(it).to contain(/other/) }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end

      it "should fail if archive entry does not exist" do
        mkpath 'resources'
        check(package.entry('resources/test')) { expect(it).to contain(/anything/) }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end
    end

    describe '#contain(path)' do

      it "should pass if archive path contains file" do
        write 'resources/test'
        check(package.path('resources')) { expect(it).to contain('test') }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should handle deep nesting" do
        write 'resources/test/test2.efx'
        check(package) { expect(it).to contain('resources/test/test2.efx') }
        check(package.path('resources')) { expect(it).to contain('test/test2.efx') }
        check(package.path('resources/test')) { expect(it).to contain('test2.efx') }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should pass if archive path contains pattern" do
        write 'resources/with/test'
        check(package.path('resources')) { expect(it).to contain('**/t*st') }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should pass if archive path contains all arguments" do
        write 'resources/with/test'
        check(package.path('resources')) { expect(it).to contain('**/test', '**/*') }
        expect { project('foo').task('package').invoke }.not_to raise_error
      end

      it "should fail unless archive path contains all arguments" do
        write 'resources/test'
        check(package.path('resources')) { expect(it).to contain('test', 'or-not') }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end

      it "should fail if archive path is empty" do
        mkpath 'resources'
        check(package.path('resources')) { expect(it).to contain('test') }
        expect { project('foo').task('package').invoke }.to raise_error(RuntimeError, /Checks failed/)
      end
    end
  end

  describe 'ZIP' do
    before { @archive = :jar }
    it_should_behave_like 'all archive types'
  end

  describe 'tar' do
    before { @archive = :tar }
    it_should_behave_like 'all archive types'
  end

  describe 'tgz' do
    before { @archive = :tgz }
    it_should_behave_like 'all archive types'
  end
end
