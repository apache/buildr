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

require File.join(File.dirname(__FILE__), '../spec_helpers')

describe Buildr::RSpec do

  def foo(*args, &prc)
    define('foo', *args) do 
      test.using :rspec
      if prc
        instance_eval(&prc)
      else
        self
      end
    end
  end

  it 'should be selected by :rspec name' do
    foo { test.framework.should eql(:rspec) }
  end

  it 'should include src/spec/ruby/**/*_spec.rb' do
    verbose true
    foo do 
      spec = _(:source, :spec, :ruby, 'some_spec.rb')
      write spec, ''
      test.invoke
      test.tests.should include(spec)
    end
  end


end if RUBY_PLATFORM =~ /java/ # RSpec

describe Buildr::JtestR do

  def foo(*args, &prc)
    define('foo', *args) do
      test.using :jtestr
      if prc
        instance_eval(&prc)
      else
        self
      end
    end
  end

  it 'should be selected by :jtestr name' do
    foo { test.framework.should eql(:jtestr) }
  end

  it 'should include src/spec/ruby/**/*_spec.rb'
  it 'should auto generate jtestr configuration'
  it 'should run runit test cases'
  it 'should use a java compiler if java sources found'
  it 'should run junit test cases'

end # JtestR

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
      write _(:source, :spec, :java, 'SomeBehaviour.java'), 'public class SomeBehaviour {}'
      JBehave.applies_to?(self).should be_true
    end
    define('two', :base_dir => 'two') do
      write _(:source, :test, :java, 'SomeBehaviour.java'), 'public class SomeBehaviour {}'
      JBehave.applies_to?(self).should be_false
    end
    define('three', :base_dir => 'three') do
      write _(:source, :spec, :java, 'SomeBehavior.java'), 'public class SomeBehavior {}'
      JBehave.applies_to?(self).should be_true
    end
    define('four', :base_dir => 'four') do
      write _(:source, :test, :java, 'SomeBehavior.java'), 'public class SomeBehavior {}'
      JBehave.applies_to?(self).should be_false
    end
  end

  it 'should be selected by :jbehave name' do
    foo { test.framework.should eql(:jbehave) }
  end

  it 'should select a java compiler for its sources' do 
    foo do
      write _(:source, :spec, :java, 'SomeBehavior.java'), 'public class SomeBehavior {}'
      test.compile.language.should eql(:java)
    end
  end

  it 'should include JBehave dependencies' do
    foo do
      test.compile.dependencies.should include(artifact("org.jbehave:jbehave:jar::#{JBehave.version}"))
      test.dependencies.should include(artifact("org.jbehave:jbehave:jar::#{JBehave.version}"))
    end
  end

  it 'should include JMock dependencies' do
    foo do
      test.compile.dependencies.should include(artifact("jmock:jmock:jar:#{JMock.version}"))
      test.dependencies.should include(artifact("jmock:jmock:jar:#{JMock.version}"))
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
      project.test.tests.should include('some.FooBehavior')
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
      project.test.tests.should include('some.MyBehaviours')
    end
  end

end # JBehave

describe Buildr::EasyB do
  
  def foo(*args, &prc)
    define('foo', *args) do
      test.using :easyb
      if prc
        instance_eval(&prc)
      else
        self
      end
    end
  end

  it 'should apply to a project having EasyB sources' do
    define('one', :base_dir => 'one') do
      write _(:source, :spec, :groovy, 'SomeBehaviour.groovy'), 'true;'
      EasyB.applies_to?(self).should be_true
    end
    define('two', :base_dir => 'two') do
      write _(:source, :test, :groovy, 'SomeBehaviour.groovy'), 'true;'
      EasyB.applies_to?(self).should be_false
    end
    define('three', :base_dir => 'three') do
      write _(:source, :spec, :groovy, 'SomeStory.groovy'), 'true;'
      EasyB.applies_to?(self).should be_true
    end
    define('four', :base_dir => 'four') do
      write _(:source, :test, :groovy, 'SomeStory.groovy'), 'true;'
      EasyB.applies_to?(self).should be_false
    end
  end

  it 'should be selected by :easyb name' do
    foo { test.framework.should eql(:easyb) }
  end

  it 'should select a java compiler if java sources are found' do
    foo do
      write _(:source, :spec, :java, 'SomeBehavior.java'), 'public class SomeBehavior {}'
      test.compile.language.should eql(:java)
    end
  end
  
  it 'should include src/spec/groovy/*Behavior.groovy' do
    foo do 
      spec = _(:source, :spec, :groovy, 'SomeBehavior.groovy')
      write spec, 'true'
      test.invoke
      test.tests.should include(spec)
    end
  end

  it 'should include src/spec/groovy/*Story.groovy' do
    foo do 
      spec = _(:source, :spec, :groovy, 'SomeStory.groovy')
      write spec, 'true'
      test.invoke
      test.tests.should include(spec)
    end
  end
  
end # EasyB


