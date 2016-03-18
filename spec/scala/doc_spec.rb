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

  it 'should pick -doc-title from project name by default' do
    define 'foo' do
      compile.using(:scalac)

      define 'bar' do
        compile.using(:scalac)
      end
    end

    expect(project('foo').doc.options[:"doc-title"]).to eql('foo')
    expect(project('foo:bar').doc.options[:"doc-title"]).to eql('foo:bar')
  end

  it 'should pick -doc-title from project description by default, if available' do
    desc 'My App'
    define 'foo' do
      compile.using(:scalac)
    end
    expect(project('foo').doc.options[:"doc-title"]).to eql('My App')
  end

  it 'should not override explicit "doc-title" option' do
    define 'foo' do
      compile.using(:scalac)
      doc.using "doc-title" => 'explicit'
    end
    expect(project('foo').doc.options[:"doc-title"]).to eql('explicit')
  end

if Java.java.lang.System.getProperty("java.runtime.version") >= "1.6"

  it 'should convert :windowtitle to -doc-title for Scala 2.8.1 and later' do
    write 'src/main/scala/com/example/Test.scala', 'package com.example; class Test { val i = 1 }'
    define('foo') do
      doc.using :windowtitle => "foo"
    end
    actual = Java.scala.tools.nsc.ScalaDoc.new
    scaladoc = Java.scala.tools.nsc.ScalaDoc.new
    expect(Java.scala.tools.nsc.ScalaDoc).to receive(:new) do
      scaladoc
    end
    expect(scaladoc).to receive(:process) do |args|
      # Convert Java Strings to Ruby Strings, if needed.
      xargs = args.map { |a| a.is_a?(String) ? a : a.toString }
      expect(xargs).to include("-doc-title")
      expect(xargs).not_to include("-windowtitle")
      expect(actual.process(args)).to eql(true)
    end
    project('foo').doc.invoke
  end unless Buildr::Scala.version?(2.7, "2.8.0")

elsif Buildr::VERSION >= '1.5'
  raise "JVM version guard in #{__FILE__} should be removed since it is assumed that Java 1.5 is no longer supported."
end

end

if Java.java.lang.System.getProperty("java.runtime.version") >= "1.6"

describe "package(:scaladoc)" do
  it "should generate target/project-version-scaladoc.jar" do
    write 'src/main/scala/Foo.scala', 'class Foo'
    define 'foo', :version=>'1.0' do
      package(:scaladoc)
    end

    scaladoc = project('foo').package(:scaladoc)
    expect(scaladoc).to point_to_path('target/foo-1.0-scaladoc.jar')

    expect {
      project('foo').task('package').invoke
    }.to change { File.exist?('target/foo-1.0-scaladoc.jar') }.to(true)

    expect(scaladoc).to exist
    expect(scaladoc).to contain('index.html')
    expect(scaladoc).to contain('Foo.html')
  end
end

elsif Buildr::VERSION >= '1.5'
  raise "JVM version guard in #{__FILE__} should be removed since it is assumed that Java 1.5 is no longer supported."
end
