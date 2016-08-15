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


describe 'ecj compiler' do
  it 'should be explicitly referenced' do
    write 'src/main/java/com/example/Test.java', 'package com.example; class Test {}'
    define('foo').compile.using(:ecj).compiler.should eql(:ecj)
  end

  it 'should report the language as :java' do
    define('foo').compile.using(:ecj).language.should eql(:java)
  end

  it 'should set the target directory to target/classes' do
    define 'foo' do
      lambda { compile.using(:ecj) }.should change { compile.target.to_s }.to(File.expand_path('target/classes'))
    end
  end

  it 'should not override existing target directory' do
    define 'foo' do
      compile.into('classes')
      lambda { compile.using(:ecj) }.should_not change { compile.target }
    end
  end

  it 'should accept a task to compile from' do
    p = define 'foo' do
      project.version = '1'
      f = file(_(:target, :generated, 'myjava')) do
        mkdir_p _(:target, :generated, 'myjava')
        File.open("#{_(:target, :generated, 'myjava')}/Foo.java", "wb") do |f|
          f.write "public class Foo {}"
        end
      end

      compile.from(f)
      package(:jar)
    end.compile.invoke
    file('target/classes/Foo.class').should exist
  end

  it 'should not change existing list of sources' do
    define 'foo' do
      compile.from('sources')
      lambda { compile.using(:ecj) }.should_not change { compile.sources }
    end
  end

  # Doesn't work under jdk1.5 - caused in one of the commits 1167678, 1170604, 1170605, 1180125
  if Java.java.lang.System.getProperty("java.runtime.version") >= "1.6"
    it 'should include classpath dependencies' do
      write 'src/dependency/Dependency.java', 'class Dependency {}'
      define 'dependency', :version=>'1.0' do
        compile.from('src/dependency').into('target/dependency')
        package(:jar)
      end
      write 'src/test/DependencyTest.java', 'class DependencyTest { Dependency _var; }'
      define('foo').compile.from('src/test').with(project('dependency')).invoke
      file('target/classes/DependencyTest.class').should exist
    end
  end
  
  it 'should include tools.jar dependency' do
    repositories.remote << "http://repo1.maven.org/maven2/"
    write 'src/main/java/UseJarSigner.java', <<-JAVA
    import sun.tools.jar.Manifest;
    public class UseJarSigner { }
    JAVA
    define('foo').compile.invoke
    file('target/classes/UseJarSigner.class').should exist
  end

  it 'should ignore package-info.java files in up-to-date check' do
    write 'src/main/java/foo/Test.java', 'package foo; class Test { public void foo() {} }'
    write 'src/main/java/foo/package-info.java', 'package foo;'
    lambda{ define('foo').compile.invoke }.should run_task('foo:compile')
    lambda{ define('bar').compile.invoke }.should_not run_task('bar:compile')
  end
end


describe 'ecj compiler options' do
  def compile_task
    @compile_task ||= define('foo').compile.using(:ecj)
  end

  def ecj_args
    compile_task.instance_eval { @compiler }.send(:ecj_args)
  end

  it 'should set warnings option to false by default' do
    compile_task.options.warnings.should be_false
  end

  it 'should set warnings option to true when running with --verbose option' do
    verbose true
    compile_task.options.warnings.should be_false
  end

  it 'should use -nowarn argument when warnings is false' do
    compile_task.using(:warnings=>false)
    ecj_args.should include('-warn:none')
  end

  it 'should not use -nowarn argument when warnings is true' do
    compile_task.using(:warnings=>true)
    ecj_args.should_not include('-warn:none')
  end

  it 'should not use -verbose argument by default' do
    ecj_args.should_not include('-verbose')
  end

  it 'should use -verbose argument when running with --trace=ecj option' do
    Buildr.application.options.trace_categories = [:ecj]
    ecj_args.should include('-verbose')
  end

  it 'should set debug option to true by default' do
    compile_task.options.debug.should be_true
  end

  it 'should set debug option to false based on Buildr.options' do
    Buildr.options.debug = false
    compile_task.options.debug.should be_false
  end

  it 'should set debug option to false based on debug environment variable' do
    ENV['debug'] = 'no'
    compile_task.options.debug.should be_false
  end

  it 'should set debug option to false based on DEBUG environment variable' do
    ENV['DEBUG'] = 'no'
    compile_task.options.debug.should be_false
  end

  it 'should use -g argument when debug option is true' do
    compile_task.using(:debug=>true)
    ecj_args.should include('-g')
  end

  it 'should not use -g argument when debug option is false' do
    compile_task.using(:debug=>false)
    ecj_args.should_not include('-g')
  end

  it 'should set deprecation option to false by default' do
    compile_task.options.deprecation.should be_false
  end

  it 'should use -deprecation argument when deprecation is true' do
    compile_task.using(:deprecation=>true)
    ecj_args.should include('-deprecation')
  end

  it 'should not use -deprecation argument when deprecation is false' do
    compile_task.using(:deprecation=>false)
    ecj_args.should_not include('-deprecation')
  end

  it 'should not set source option by default' do
    compile_task.options.source.should be_nil
    ecj_args.should_not include('-source')
  end

  it 'should not set target option by default' do
    compile_task.options.target.should be_nil
    ecj_args.should_not include('-target')
  end

  it 'should use -source nn argument if source option set' do
    compile_task.using(:source=>'1.5')
    ecj_args.should include('-source', '1.5')
  end

  it 'should use -target nn argument if target option set' do
    compile_task.using(:target=>'1.5')
    ecj_args.should include('-target', '1.5')
  end

  it 'should set lint option to false by default' do
    compile_task.options.lint.should be_false
  end

  it 'should use -lint argument if lint option is true' do
    compile_task.using(:lint=>true)
    ecj_args.should include('-Xlint')
  end

  it 'should use -lint argument with value of option' do
    compile_task.using(:lint=>'all')
    ecj_args.should include('-Xlint:all')
  end

  it 'should use -lint argument with value of option as array' do
    compile_task.using(:lint=>['path', 'serial'])
    ecj_args.should include('-Xlint:path,serial')
  end

  it 'should not set other option by default' do
    compile_task.options.other.should be_nil
  end

  it 'should pass other argument if other option is string' do
    compile_task.using(:other=>'-Xprint')
    ecj_args.should include('-Xprint')
  end

  it 'should pass other argument if other option is array' do
    compile_task.using(:other=>['-Xstdout', 'msgs'])
    ecj_args.should include('-Xstdout', 'msgs')
  end

  it 'should complain about options it doesn\'t know' do
    repositories.remote << "http://repo1.maven.org/maven2/"
    write 'source/Test.java', 'class Test {}'
    compile_task.using(:unknown=>'option')
    lambda { compile_task.from('source').invoke }.should raise_error(ArgumentError, /no such option/i)
  end

  it 'should inherit options from parent' do
    define 'foo' do
      compile.using(:warnings=>true, :debug=>true, :deprecation=>true, :source=>'1.5', :target=>'1.4')
      define 'bar' do
        compile.using(:ecj)
        compile.options.warnings.should be_true
        compile.options.debug.should be_true
        compile.options.deprecation.should be_true
        compile.options.source.should eql('1.5')
        compile.options.target.should eql('1.4')
      end
    end
  end

  after do
    Buildr.options.debug = nil
    ENV.delete "debug"
    ENV.delete "DEBUG"
  end

  # Redirect the java error ouput, yielding so you can do something while it is
  # and returning the content of the error buffer.
  #
  def redirect_java_err
    err = Java.java.io.ByteArrayOutputStream.new
    original_err = Java.java.lang.System.err
    begin
      printStream = Java.java.io.PrintStream
      print = printStream.new(err)
      Java.java.lang.System.setErr(print)
      yield
    ensure
      Java.java.lang.System.setErr(original_err)
    end
    err.toString
  end

  it "should not issue warnings for type casting when warnings are set to warn:none, by default" do
    write "src/main/java/Main.java", "import java.util.List; public class Main {public List get() {return null;}}"
    foo = define("foo") {
      compile.options.source = "1.5"
      compile.options.target = "1.5"
    }
    redirect_java_err { foo.compile.invoke }.should_not match(/warning/)
  end

  it "should issue warnings for type casting when warnings are set" do
    write "src/main/java/Main.java", "import java.util.List; public class Main {public List get() {return null;}}"
    foo = define("foo") {
      compile.options.source = "1.5"
      compile.options.target = "1.5"
      compile.options.warnings = true
    }
    redirect_java_err { foo.compile.invoke }.should match(/warning/)
  end
  
  it 'should pick Ecj version from ecj build settings' do
    begin
      Buildr::Compiler::Ecj.instance_eval { @dependencies = nil }
      write 'build.yaml', 'ecj: 3.5.1'
      Buildr::Compiler::Ecj.dependencies.should include("org.eclipse.jdt.core.compiler:ecj:jar:3.5.1")
    ensure
      Buildr::Compiler::Ecj.instance_eval { @dependencies = nil }
    end
  end

end
