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


require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helpers'))

describe Buildr::VersionRequirement, '.create' do
  def create(str)
    Buildr::VersionRequirement.create(str)
  end

  it 'should complain on invalid input' do
    expect { create }.to raise_error(Exception)
    expect { create('%') }.to raise_error(Exception, /invalid character/)
    expect { create('1#{0}') }.to raise_error(Exception, /invalid character/)
    expect { create('1.0rc`exit`') }.to raise_error(Exception, /invalid character/)
    expect { create(1.0) }.to raise_error(Exception)
    expect { create('1.0') }.not_to raise_error
    expect { create('1.0rc3') }.not_to raise_error
  end

  it 'should allow versions using hyphen' do
    expect { create('1.0-rc3') }.not_to raise_error
  end

  it 'should create a single version requirement' do
    expect(create('1.0')).not_to be_composed
  end

  it 'should create a composed version requirement' do
    expect(create('1.0 | 2.1')).to be_composed
  end
end

=begin
# TODO: Fix this.
# 1.  Can't use should_satisfy, this breaks under RSpec 1.2
# 2.  These should_satisfy calls are not proper specs since the subject is
#     the satistifed_by? method. satisfied_by should satisfy???
describe Buildr::VersionRequirement, '#satisfied_by?' do
  def should_satisfy(str, valids = [], invalids = [])
    req = Buildr::VersionRequirement.create(str)
    valids.each { |v| req.should be_satisfied_by(v) }
    invalids.each { |v| req.should_not be_satisfied_by(v) }
  end

  it 'should accept Gem version operators' do
    should_satisfy '1.0', %w(1 1.0), %w(1.1 0.1)
    should_satisfy '=1.0', %w(1 1.0), %w(1.1 0.1)
    should_satisfy '= 1.0', %w(1 1.0), %w(1.1 0.1)
    should_satisfy '!= 1.0', %w(0.9 1.1 2), %w(1 1.0 1.0.0)

    should_satisfy '>1.0', %w(1.0.1), %w(1 1.0 0.1)
    should_satisfy '>=1.0', %w(1.0.1 1 1.0), %w(0.9)

    should_satisfy '<1.0', %w(0.9 0.9.9), %w(1 1.0 1.1 2)
    should_satisfy '<=1.0', %w(0.9 0.9.9 1 1.0), %w(1.1 2)

    should_satisfy '~> 1.2.3', %w(1.2.3 1.2.3.4 1.2.4), %w(1.2.1 0.9 1.4 2)
  end

  it 'should accept logic not operator' do
    should_satisfy 'not 0.5', %w(0 1), %w(0.5)
    should_satisfy '!  0.5', %w(0 1), %w(0.5)
    should_satisfy '!= 0.5', %w(0 1), %w(0.5)
    should_satisfy '!<= 0.5', %w(0.5.1 2), %w(0.5)
  end

  it 'should accept logic or operator' do
    should_satisfy '0.5 or 2.0', %w(0.5 2.0), %w(1.0 0.5.1 2.0.9)
    should_satisfy '0.5 | 2.0', %w(0.5 2.0), %w(1.0 0.5.1 2.0.9)
  end

  it 'should accept logic and operator' do
    should_satisfy '>1.5 and <2.0', %w(1.6 1.9), %w(1.5 2 2.0)
    should_satisfy '>1.5 & <2.0', %w(1.6 1.9), %w(1.5 2 2.0)
  end

  it 'should assume logic and if missing operator between expressions' do
    should_satisfy '>1.5 <2.0', %w(1.6 1.9), %w(1.5 2 2.0)
  end

  it 'should allow combining logic operators' do
    should_satisfy '>1.0 | <2.0 | =3.0', %w(1.5 3.0 1 2 4)
    should_satisfy '>1.0 & <2.0 | =3.0', %w(1.3 3.0), %w(1 2)
    should_satisfy '=1.0 | <2.0 & =0.5', %w(0.5 1.0), %w(1.1 0.1 2)
    should_satisfy '~>1.1 | ~>1.3 | ~>1.5 | 2.0', %w(2 1.5.6 1.1.2 1.1.3), %w(1.0.9 0.5 2.2.1)
    should_satisfy 'not(2) | 1', %w(1 3), %w(2)
  end

  it 'should allow using parens to group logic expressions' do
    should_satisfy '(1.0)', %w(1 1.0), %w(0.9 1.1)
    should_satisfy '!( !(1.0) )', %w(1 1.0), %w(0.9 1.1)
    should_satisfy '1 | !(2 | 3)', %w(1), %w(2 3)
    should_satisfy '!(2 | 3) | 1', %w(1), %w(2 3)
  end
end
=end

describe Buildr::VersionRequirement, '#default' do
  it 'should return nil if missing default requirement' do
    expect(Buildr::VersionRequirement.create('>1').default).to be_nil
    expect(Buildr::VersionRequirement.create('<1').default).to be_nil
    expect(Buildr::VersionRequirement.create('!1').default).to be_nil
    expect(Buildr::VersionRequirement.create('!<=1').default).to be_nil
  end

  it 'should return the last version with a = requirement' do
    expect(Buildr::VersionRequirement.create('1').default).to eq('1')
    expect(Buildr::VersionRequirement.create('=1').default).to eq('1')
    expect(Buildr::VersionRequirement.create('<=1').default).to eq('1')
    expect(Buildr::VersionRequirement.create('>=1').default).to eq('1')
    expect(Buildr::VersionRequirement.create('1 | 2 | 3').default).to eq('3')
    expect(Buildr::VersionRequirement.create('1 2 | 3').default).to eq('3')
    expect(Buildr::VersionRequirement.create('1 & 2 | 3').default).to eq('3')
  end
end

describe Buildr::VersionRequirement, '#version?' do
  it 'should identify valid versions' do
    expect(Buildr::VersionRequirement.version?('1')).to be_truthy
    expect(Buildr::VersionRequirement.version?('1a')).to be_truthy
    expect(Buildr::VersionRequirement.version?('1.0')).to be_truthy
    expect(Buildr::VersionRequirement.version?('11.0')).to be_truthy
    expect(Buildr::VersionRequirement.version?(' 11.0 ')).to be_truthy
    expect(Buildr::VersionRequirement.version?('11.0-alpha')).to be_truthy
    expect(Buildr::VersionRequirement.version?('r09')).to be_truthy # BUILDR-615: com.google.guava:guava:jar:r09

    expect(Buildr::VersionRequirement.version?('a')).to be_falsey
    expect(Buildr::VersionRequirement.version?('a1')).to be_falsey
    expect(Buildr::VersionRequirement.version?('r')).to be_falsey
  end
end
