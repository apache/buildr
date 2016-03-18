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

describe 'groovyc compiler' do

  it 'should identify itself from groovy source directories' do
    write 'src/main/groovy/some/Hello.groovy', 'println "Hello Groovy"'
    write 'src/test/groovy/some/Hello.groovy', 'println "Hello Groovy"'
    define('foo') do
      expect(compile.compiler).to eql(:groovyc)
      expect(test.compile.compiler).to eql(:groovyc)
    end
  end

  it 'should identify if groovy sources are found on java directories' do
    write 'src/main/java/some/Hello.groovy', 'println "Hello Groovy"'
    write 'src/test/java/some/Hello.groovy', 'println "Hello Groovy"'
    define('foo') do
      expect(compile.compiler).to eql(:groovyc)
      expect(test.compile.compiler).to eql(:groovyc)
    end
  end

  it 'should identify itself even if groovy and java sources are found' do
    write 'src/main/java/some/Empty.java', 'package some; public interface Empty {}'
    write 'src/main/groovy/some/Hello.groovy', 'println "Hello Groovy"'
    write 'src/test/java/some/Empty.java', 'package some; public interface Empty {}'
    write 'src/test/groovy/some/Hello.groovy', 'println "Hello Groovy"'
    define('foo') do
      expect(compile.compiler).to eql(:groovyc)
      expect(test.compile.compiler).to eql(:groovyc)
    end
  end

  it 'should identify from custom layout' do
    write 'groovy/Hello.groovy', 'println "Hello world"'
    write 'testing/Hello.groovy', 'println "Hello world"'
    custom = Layout.new
    custom[:source, :main, :groovy] = 'groovy'
    custom[:source, :test, :groovy] = 'testing'
    define 'foo', :layout=>custom do
      expect(compile.compiler).to eql(:groovyc)
      expect(test.compile.compiler).to eql(:groovyc)
    end
  end

  it 'should identify from compile source directories' do
    write 'src/com/example/Code.groovy', 'println "monkey code"'
    write 'testing/com/example/Test.groovy', 'println "some test"'
    define 'foo' do
      expect { compile.from 'src' }.to change { compile.compiler }.to(:groovyc)
      expect { test.compile.from 'testing' }.to change { test.compile.compiler }.to(:groovyc)
    end
  end

  it 'should report the multi-language as :groovy, :java' do
    expect(define('foo').compile.using(:groovyc).language).to eq(:groovy)
  end

  it 'should set the target directory to target/classes' do
    define 'foo' do
      expect { compile.using(:groovyc) }.to change { compile.target.to_s }.to(File.expand_path('target/classes'))
    end
  end

  it 'should not override existing target directory' do
    define 'foo' do
      compile.into('classes')
      expect { compile.using(:groovyc) }.not_to change { compile.target }
    end
  end

  it 'should not change existing list of sources' do
    define 'foo' do
      compile.from('sources')
      expect { compile.using(:groovyc) }.not_to change { compile.sources }
    end
  end

  it 'should compile groovy sources' do
    write 'src/main/groovy/some/Example.groovy', 'package some; class Example { static main(args) { println "Hello" } }'
    define('foo').compile.invoke
    expect(file('target/classes/some/Example.class')).to exist
  end

  it 'should compile test groovy sources that rely on junit' do
    write 'src/main/groovy/some/Example.groovy', 'package some; class Example { static main(args) { println "Hello" } }'
    write 'src/test/groovy/some/ExampleTest.groovy', "package some\n import junit.framework.TestCase\n class ExampleTest extends TestCase { public testHello() { println \"Hello\" } }"
    foo = define('foo') do
      test.using :junit
    end
    foo.test.compile.invoke
    expect(file('target/classes/some/Example.class')).to exist
    expect(file('target/test/classes/some/ExampleTest.class')).to exist
  end

  it 'should include as classpath dependency' do
    write 'src/bar/groovy/some/Foo.groovy', 'package some; interface Foo {}'
    write 'src/main/groovy/some/Example.groovy', 'package some; class Example implements Foo { }'
    define('bar', :version => '1.0') do
      compile.from('src/bar/groovy').into('target/bar')
      package(:jar)
    end
    expect { define('foo').compile.with(project('bar').package(:jar)).invoke }.to run_task('foo:compile')
    expect(file('target/classes/some/Example.class')).to exist
  end

  it 'should cross compile java sources' do
    write 'src/main/java/some/Foo.java', 'package some; public interface Foo { public void hello(); }'
    write 'src/main/java/some/Baz.java', 'package some; public class Baz extends Bar { }'
    write 'src/main/groovy/some/Bar.groovy', 'package some; class Bar implements Foo { def void hello() { } }'
    define('foo').compile.invoke
    %w{Foo Bar Baz}.each { |f| expect(file("target/classes/some/#{f}.class")).to exist }
  end

  it 'should cross compile test java sources' do
    write 'src/test/java/some/Foo.java', 'package some; public interface Foo { public void hello(); }'
    write 'src/test/java/some/Baz.java', 'package some; public class Baz extends Bar { }'
    write 'src/test/groovy/some/Bar.groovy', 'package some; class Bar implements Foo { def void hello() { } }'
    define('foo').test.compile.invoke
    %w{Foo Bar Baz}.each { |f| expect(file("target/test/classes/some/#{f}.class")).to exist }
  end

  it 'should package classes into a jar file' do
    write 'src/main/groovy/some/Example.groovy', 'package some; class Example { }'
    define('foo', :version => '1.0').package.invoke
    expect(file('target/foo-1.0.jar')).to exist
    Zip::File.open(project('foo').package(:jar).to_s) do |jar|
      expect(jar.exist?('some/Example.class')).to be_truthy
    end
  end

end

describe 'groovyc compiler options' do

  def groovyc(&prc)
    define('foo') do
      compile.using(:groovyc)
      @compiler = compile.instance_eval { @compiler }
      class << @compiler
        public :groovyc_options, :javac_options
      end
      if block_given?
        instance_eval(&prc)
      else
        return compile
      end
    end
    project('foo').compile
  end

  it 'should set warning option to false by default' do
    groovyc do
      expect(compile.options.warnings).to be_falsey
      expect(@compiler.javac_options[:nowarn]).to be_truthy
    end
  end

  it 'should set warning option to true when running with --verbose option' do
    verbose true
    groovyc do
      expect(compile.options.warnings).to be_truthy
      expect(@compiler.javac_options[:nowarn]).to be_falsey
    end
  end

  it 'should not set verbose option by default' do
    expect(groovyc.options.verbose).to be_falsey
  end

  it 'should set verbose option when running with --trace=groovyc option' do
    Buildr.application.options.trace_categories = [:groovyc]
    expect(groovyc.options.verbose).to be_truthy
  end

  it 'should set debug option to false based on Buildr.options' do
    Buildr.options.debug = false
    expect(groovyc.options.debug).to be_falsey
  end

  it 'should set debug option to false based on debug environment variable' do
    ENV['debug'] = 'no'
    expect(groovyc.options.debug).to be_falsey
  end

  it 'should set debug option to false based on DEBUG environment variable' do
    ENV['DEBUG'] = 'no'
    expect(groovyc.options.debug).to be_falsey
  end

  it 'should set deprecation option to false by default' do
    expect(groovyc.options.deprecation).to be_falsey
  end

  it 'should use deprecation argument when deprecation is true' do
    groovyc do
      compile.using(:deprecation=>true)
      expect(compile.options.deprecation).to be_truthy
      expect(@compiler.javac_options[:deprecation]).to be_truthy
    end
  end

  it 'should not use deprecation argument when deprecation is false' do
    groovyc do
      compile.using(:deprecation=>false)
      expect(compile.options.deprecation).to be_falsey
      expect(@compiler.javac_options[:deprecation]).not_to be_truthy
    end
  end

  it 'should set optimise option to false by default' do
    expect(groovyc.options.optimise).to be_falsey
  end

  it 'should use optimize argument when deprecation is true' do
    groovyc do
      compile.using(:optimise=>true)
      expect(@compiler.javac_options[:optimize]).to be_truthy
    end
  end

  it 'should not use optimize argument when deprecation is false' do
    groovyc do
      compile.using(:optimise=>false)
      expect(@compiler.javac_options[:optimize]).to be_falsey
    end
  end

  after do
    Buildr.options.debug = nil
    ENV.delete "debug"
    ENV.delete "DEBUG"
  end

end
