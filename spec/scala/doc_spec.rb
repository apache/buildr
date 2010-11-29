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

describe "Scaladoc" do

  before(:each) do
    # Force Scala 2.8.1 for specs; don't want to rely on SCALA_HOME
    Buildr.settings.build['scala.version'] = "2.8.1"
  end

  it 'should pick -doc-title from project name by default' do
    define 'foo' do
      compile.using(:scalac)

      define 'bar' do
        compile.using(:scalac)
      end
    end

    project('foo').doc.options[:"doc-title"].should eql('foo')
    project('foo:bar').doc.options[:"doc-title"].should eql('foo:bar')
  end

  it 'should pick -doc-title from project description by default, if available' do
    desc 'My App'
    define 'foo' do
      compile.using(:scalac)
    end
    project('foo').doc.options[:"doc-title"].should eql('My App')
  end

  it 'should not override explicit "doc-title" option' do
    define 'foo' do
      compile.using(:scalac)
      doc.using "doc-title" => 'explicit'
    end
    project('foo').doc.options[:"doc-title"].should eql('explicit')
  end

  it 'should convert :windowtitle to -doc-title for Scala 2.8.1' do
    write 'src/main/scala/com/example/Test.scala', 'package com.example; class Test { val i = 1 }'
    define('foo') do
      doc.using :windowtitle => "foo"
    end
    Java.scala.tools.nsc.ScalaDoc.should_receive(:main) do |args|
      # Convert Java Strings to Ruby Strings, if needed.
      args.map { |a| a.is_a?(String) ? a : a.toString }.should include("-doc-title")
      0 # normal return
    end
    project('foo').doc.invoke
  end

end
