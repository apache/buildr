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

# need to test both with and without KOTLIN_HOME
RSpec.shared_examples 'KotlincCompiler' do

  it 'should identify itself from source directories' do
    write 'src/main/kotlin/com/example/Test.kt', "package com.example\n class Test { }"
    define('foo').compile.compiler.should eql(:kotlinc)
  end

  it 'should report the language as :kotlin' do
    define('foo').compile.using(:kotlinc).language.should eql(:kotlin)
  end

  it 'should set the target directory to target/classes' do
    define 'foo' do
      lambda { compile.using(:kotlinc) }.should change { compile.target.to_s }.to(File.expand_path('target/classes'))
    end
  end

  it 'should not override existing target directory' do
    define 'foo' do
      compile.into('classes')
      lambda { compile.using(:kotlinc) }.should_not change { compile.target }
    end
  end

  it 'should not change existing list of sources' do
    define 'foo' do
      compile.from('sources')
      lambda { compile.using(:kotlinc) }.should_not change { compile.sources }
    end
  end

  it 'should include as classpath dependency' do
    write 'src/dependency/Dependency.kt', 'class Dependency {}'
    define 'dependency', :version=>'1.0' do
      compile.from('src/dependency').into('target/dependency')
      package(:jar)
    end
    write 'src/test/DependencyTest.kt', "class DependencyTest { val d = Dependency() }"
    lambda { define('foo').compile.from('src/test').with(project('dependency')).invoke }.should run_task('foo:compile')
    file('target/classes/DependencyTest.class').should exist
  end

  def define_test1_project
    write 'src/main/kotlin/com/example/Test1.kt', "// file name: Test1.kt\npackage com.example\nclass Test1 {}"
    define 'test1', :version=>'1.0' do
      package(:jar)
    end
  end

  it 'should compile a simple .kt file into a .class file' do
    define_test1_project
    task('test1:compile').invoke
    file('target/classes/com/example/Test1.class').should exist
  end

  it 'should package .class into a .jar file' do
    define_test1_project
    task('test1:package').invoke
    file('target/test1-1.0.jar').should exist
    Zip::File.open(project('test1').package(:jar).to_s) do |zip|
      zip.exist?('com/example/Test1.class').should be_true
    end
  end

  it 'should compile kotlin class depending on java class in same project' do
    write 'src/main/java/com/example/Foo.java', 'package com.example; public class Foo {}'
    write 'src/main/kotlin/com/example/Bar.kt', "package com.example\n class Bar() : Foo() {}"
    define 'test1', :version=>'1.0' do
      package(:jar)
    end
    task('test1:package').invoke
    file('target/test1-1.0.jar').should exist
    Zip::File.open(project('test1').package(:jar).to_s) do |zip|
      zip.exist?('com/example/Foo.class').should be_true
      zip.exist?('com/example/Bar.class').should be_true
    end
  end

  it 'should compile java class depending on kotlin class in same project' do
    write 'src/main/kotlin/com/example/Foo.kt', 'package com.example; open class Foo'
    write 'src/main/java/com/example/Bar.java',  'package com.example; public class Bar extends Foo {}'
    define 'test1', :version=>'1.0' do
      package(:jar)
    end
    task('test1:package').invoke
    file('target/test1-1.0.jar').should exist
    Zip::File.open(project('test1').package(:jar).to_s) do |zip|
      zip.exist?('com/example/Foo.class').should be_true
      zip.exist?('com/example/Bar.class').should be_true
    end
  end
end

RSpec.shared_examples 'KotlincCompiler_CommonOptions' do

  it 'should set warnings option to false by default' do
    compile_task.options.warnings.should be_false
  end

  it 'should set warnings option to true when running with --verbose option' do
    verbose true
    compile_task.options.warnings.should be_true
  end

  it 'should use -nowarn argument when warnings is false' do
    compile_task.using(:warnings=>false)
    kotlinc_args.suppressWarnings.should be_true
  end

  it 'should not use -nowarn argument when warnings is true' do
    compile_task.using(:warnings=>true)
    kotlinc_args.suppressWarnings.should be_false
  end

  it 'should not use -verbose argument by default' do
    oldDebug = Buildr.options.debug
    Buildr.options.debug = false
    begin
      kotlinc_args.verbose.should eql(false)
    ensure
      Buildr.options.debug = oldDebug
    end
  end

  it 'should use -verbose argument when running with --trace=kotlinc option' do
    Buildr.application.options.trace_categories = [:kotlinc]
    kotlinc_args.verbose.should eql(true)
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

  it 'should set deprecation option to false by default' do
    compile_task.options.deprecation.should be_false
  end

  it 'should set optimise option to false by default' do
    compile_task.options.optimize.should be_false
  end

  it 'should use -optimise argument when deprecation is true' do
    compile_task.using(:optimize=>true)
    kotlinc_args.noOptimize.should be_false
  end

  it 'should not use -optimise argument when deprecation is false' do
    compile_task.using(:optimize=>false)
    kotlinc_args.noOptimize.should be_true
  end

  it 'should set noStdlib option to true by default' do
    compile_task.options.noStdlib.should be_true
    kotlinc_args.noStdlib.should be_true
  end

  it 'should not set target option by default' do
    compile_task.options.target.should be_nil
    kotlinc_args.jvmTarget.should be_nil
  end

  it 'should use -target:xxx argument if target option set' do
    compile_task.using(:target=>'1.5')
    kotlinc_args.jvmTarget.should eql('1.5')
  end

  it 'should not set other option by default' do
    compile_task.options.other.should be_nil
  end

  it 'should complain about options it doesn\'t know' do
    write 'source/Test.kt', 'class Test {}'
    compile_task.using(:unknown=>'option')
    lambda { compile_task.from('source').invoke }.should raise_error(ArgumentError, /no such option/i)
  end

  it 'should inherit options from parent' do
    define 'foo' do
      compile.using(:noStdlib=>false, :warnings=>true, :target=>'1.8')
      define 'bar' do
        compile.using(:kotlinc)
        compile.options.noStdlib.should be_false
        compile.options.warnings.should be_true
        compile.options.target.should eql('1.8')
      end
    end
  end

  after do
    Buildr.options.debug = nil
    ENV.delete "debug"
    ENV.delete "DEBUG"
  end
end

if Java.java.lang.System.getProperty("java.runtime.version") >= "1.8"
  # Only run this test if the test environment has KOTLIN_HOME specified.
  # Allows the Test Suite to run on TravisCI
  if ENV['KOTLIN_HOME']
    describe 'kotlin compiler (installed in KOTLIN_HOME)' do
      it 'requires present KOTLIN_HOME' do
        ENV['KOTLIN_HOME'].should_not be_nil
      end

      def compile_task
        @compile_task ||= define('foo').compile.using(:kotlinc)
      end

      it_should_behave_like 'KotlincCompiler'
      it_should_behave_like 'KotlincCompiler_CommonOptions'
    end
  end

  describe 'kotlin compiler (downloaded from repository)' do
    old_home = ENV['KOTLIN_HOME']

    before :all do
      ENV['KOTLIN_HOME'] = nil
    end

    it 'requires absent KOTLIN_HOME' do
      ENV['KOTLIN_HOME'].should be_nil
    end

    def compile_task
      @compile_task ||= define('foo').compile.using(:kotlinc)
    end

    def kotlinc_args
      compile_task.instance_eval { @compiler }.send(:kotlinc_args)
    end

    it_should_behave_like 'KotlincCompiler'
    it_should_behave_like 'KotlincCompiler_CommonOptions'

    after :all do
      ENV['KOTLIN_HOME'] = old_home
    end
  end
end
