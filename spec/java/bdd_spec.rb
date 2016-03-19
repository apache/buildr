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

describe Buildr::RSpec do

  before(:each) do
    define('foo') do
      test.using :rspec, :output => false
    end
  end

  it 'should be selected by :rspec name' do
    expect(project('foo').test.framework).to eql(:rspec)
  end

  # These tests will fail because they expect that a version of rspec will be present in the local gem
  # repository for the jruby that comes out of the maven repository but this is not the case. Disabling
  # These across the board until someone wants to invest the time in refactoring them to work
  if false
    it 'should read passed specs from result yaml' do
      write('src/spec/ruby/success_spec.rb', 'describe("success") { it("is true") { nil.should be_nil } }')

      project('foo').test.invoke
      expect(project('foo').test.passed_tests).to eql([File.expand_path('src/spec/ruby/success_spec.rb')])
    end

    it 'should read result yaml to obtain the list of failed specs' do
      success = File.expand_path('src/spec/ruby/success_spec.rb')
      write(success, 'describe("success") { it("is true") { nil.should be_nil } }')
      failure = File.expand_path('src/spec/ruby/failure_spec.rb')
      write(failure, 'describe("failure") { it("is false") { true.should == false } }')
      error = File.expand_path('src/spec/ruby/error_spec.rb')
      write(error, 'describe("error") { it("raises") { lambda; } }')

      expect { project('foo').test.invoke }.to raise_error(/Tests failed/)
      expect(project('foo').test.tests).to include(success, failure, error)
      expect(project('foo').test.failed_tests.sort).to eql([failure, error].sort)
      expect(project('foo').test.passed_tests).to eql([success])
    end
  end

end if RUBY_PLATFORM =~ /java/ || ENV['JRUBY_HOME'] # RSpec

describe Buildr::JBehave do
  def foo(*args, &prc)
    define('foo', *args) do
      test.using :jbehave
      if prc
        instance_eval(&prc)
      else
        self
      end
    end
  end

  it 'should apply to projects having JBehave sources' do
    define('one', :base_dir => 'one') do
      write _('src/spec/java/SomeBehaviour.java'), 'public class SomeBehaviour {}'
      expect(JBehave.applies_to?(self)).to be_truthy
    end
    define('two', :base_dir => 'two') do
      write _('src/test/java/SomeBehaviour.java'), 'public class SomeBehaviour {}'
      expect(JBehave.applies_to?(self)).to be_falsey
    end
    define('three', :base_dir => 'three') do
      write _('src/spec/java/SomeBehavior.java'), 'public class SomeBehavior {}'
      expect(JBehave.applies_to?(self)).to be_truthy
    end
    define('four', :base_dir => 'four') do
      write _('src/test/java/SomeBehavior.java'), 'public class SomeBehavior {}'
      expect(JBehave.applies_to?(self)).to be_falsey
    end
  end

  it 'should be selected by :jbehave name' do
    foo { expect(test.framework).to eql(:jbehave) }
  end

  it 'should select a java compiler for its sources' do
    write 'src/test/java/SomeBehavior.java', 'public class SomeBehavior {}'
    foo do
      expect(test.compile.language).to eql(:java)
    end
  end

  it 'should include JBehave dependencies' do
    foo do
      expect(test.compile.dependencies).to include(artifact("org.jbehave:jbehave:jar::#{JBehave.version}"))
      expect(test.dependencies).to include(artifact("org.jbehave:jbehave:jar::#{JBehave.version}"))
    end
  end

  it 'should include JMock dependencies' do
    foo do
      two_or_later = JMock.version[0,1].to_i >= 2
      group = two_or_later ? "org.jmock" : "jmock"
      expect(test.compile.dependencies).to include(artifact("#{group}:jmock:jar:#{JMock.version}"))
      expect(test.dependencies).to include(artifact("#{group}:jmock:jar:#{JMock.version}"))
    end
  end

  it 'should include classes whose name ends with Behavior' do
    write 'src/spec/java/some/FooBehavior.java', <<-JAVA
      package some;
      public class FooBehavior {
        public void shouldFoo() { assert true; }
      }
    JAVA
    write 'src/spec/java/some/NotATest.java', <<-JAVA
      package some;
      public class NotATest { }
    JAVA
    foo.tap do |project|
      project.test.invoke
      expect(project.test.tests).to include('some.FooBehavior')
    end
  end


  it 'should include classes implementing Behaviours' do
    write 'src/spec/java/some/MyBehaviours.java',  <<-JAVA
      package some;
      public class MyBehaviours implements
      org.jbehave.core.behaviour.Behaviours {
        public Class[] getBehaviours() {
           return new Class[] { some.FooBehave.class };
        }
      }
    JAVA
    write 'src/spec/java/some/FooBehave.java', <<-JAVA
      package some;
      public class FooBehave {
        public void shouldFoo() { assert true; }
      }
    JAVA
    write 'src/spec/java/some/NotATest.java', <<-JAVA
      package some;
      public class NotATest { }
    JAVA
    foo.tap do |project|
      project.test.invoke
      expect(project.test.tests).to include('some.MyBehaviours')
    end
  end

end # JBehave
