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


describe Buildr::Groovy::EasyB do

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
      write _('src/spec/groovy/SomeSpecification.groovy'), 'true;'
      expect(Buildr::Groovy::EasyB.applies_to?(self)).to be_truthy
    end
    define('two', :base_dir => 'two') do
      write _('src/test/groovy/SomeSpecification.groovy'), 'true;'
      expect(Buildr::Groovy::EasyB.applies_to?(self)).to be_falsey
    end
    define('three', :base_dir => 'three') do
      write _('src/spec/groovy/SomeStory.groovy'), 'true;'
      expect(Buildr::Groovy::EasyB.applies_to?(self)).to be_truthy
    end
    define('four', :base_dir => 'four') do
      write _('src/test/groovy/SomeStory.groovy'), 'true;'
      expect(Buildr::Groovy::EasyB.applies_to?(self)).to be_falsey
    end
  end

  it 'should be selected by :easyb name' do
    foo { expect(test.framework).to eql(:easyb) }
  end

  it 'should select a java compiler if java sources are found' do
    foo do
      write _('src/spec/java/SomeSpecification.java'), 'public class SomeSpecification {}'
      expect(test.compile.language).to eql(:java)
    end
  end

  it 'should include src/spec/groovy/*Specification.groovy' do
    foo do
      spec = _('src/spec/groovy/SomeSpecification.groovy')
      write spec, 'true'
      test.invoke
      expect(test.tests).to include(spec)
    end
  end

  it 'should include src/spec/groovy/*Story.groovy' do
    foo do
      spec = _('src/spec/groovy/SomeStory.groovy')
      write spec, 'true'
      test.invoke
      expect(test.tests).to include(spec)
    end
  end

end # EasyB
