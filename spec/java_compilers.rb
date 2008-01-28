require File.join(File.dirname(__FILE__), 'spec_helpers')


describe 'javac compiler' do
  it 'should identify itself from source directories' do
    write 'src/main/java/com/example/Test.java', 'package com.example; class Test {}' 
    define('foo').compile.compiler.should eql(:javac)
  end

  it 'should report the language as :java' do
    define('foo').compile.using(:javac).language.should eql(:java)
  end

  it 'should set the target directory to target/classes' do
    define 'foo' do
      lambda { compile.using(:javac) }.should change { compile.target.to_s }.to(File.expand_path('target/classes'))
    end
  end

  it 'should not override existing target directory' do
    define 'foo' do
      compile.into('classes')
      lambda { compile.using(:javac) }.should_not change { compile.target }
    end
  end

  it 'should not change existing list of sources' do
    define 'foo' do
      compile.from('sources')
      lambda { compile.using(:javac) }.should_not change { compile.sources }
    end
  end

  it 'should include classpath dependencies' do
    write 'src/dependency/Dependency.java', 'class Dependency {}'
    define 'dependency', :version=>'1.0' do
      compile.from('src/dependency').into('target/dependency')
      package(:jar)
    end
    write 'src/test/DependencyTest.java', 'class DependencyTest { Dependency _var; }'
    lambda { define('foo').compile.from('src/test').with(project('dependency')).invoke }.should run_task('foo:compile')
  end
end


describe 'javac compiler options' do
  def compile_task
    @compile_task ||= define('foo').compile.using(:javac)
  end

  def javac_args
    Compiler::Javac.new(compile_task.options).send(:javac_args)
  end

  it 'should set warnings option to false by default' do
    compile_task.options.warnings.should be_false
  end

  it 'should set wranings option to true when running with --verbose option' do
    verbose true
    compile_task.options.warnings.should be_true
  end

  it 'should use -nowarn argument when warnings is false' do
    compile_task.using(:warnings=>false)
    javac_args.should include('-nowarn') 
  end

  it 'should not use -nowarn argument when warnings is true' do
    compile_task.using(:warnings=>true)
    javac_args.should_not include('-nowarn') 
  end

  it 'should not use -verbose argument by default' do
    javac_args.should_not include('-verbose') 
  end

  it 'should use -verbose argument when running with --trace option' do
    trace true
    javac_args.should include('-verbose') 
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
    javac_args.should include('-g')
  end

  it 'should not use -g argument when debug option is false' do
    compile_task.using(:debug=>false)
    javac_args.should_not include('-g')
  end

  it 'should set deprecation option to false by default' do
    compile_task.options.deprecation.should be_false
  end

  it 'should use -deprecation argument when deprecation is true' do
    compile_task.using(:deprecation=>true)
    javac_args.should include('-deprecation')
  end

  it 'should not use -deprecation argument when deprecation is false' do
    compile_task.using(:deprecation=>false)
    javac_args.should_not include('-deprecation')
  end

  it 'should not set source option by default' do
    compile_task.options.source.should be_nil
    javac_args.should_not include('-source')
  end

  it 'should not set target option by default' do
    compile_task.options.target.should be_nil
    javac_args.should_not include('-target')
  end

  it 'should use -source nn argument if source option set' do
    compile_task.using(:source=>'1.5')
    javac_args.should include('-source', '1.5')
  end

  it 'should use -target nn argument if target option set' do
    compile_task.using(:target=>'1.5')
    javac_args.should include('-target', '1.5')
  end

  it 'should set lint option to false by default' do
    compile_task.options.lint.should be_false
  end

  it 'should use -lint argument if lint option is true' do
    compile_task.using(:lint=>true)
    javac_args.should include('-Xlint')
  end

  it 'should use -lint argument with value of option' do
    compile_task.using(:lint=>'all')
    javac_args.should include('-Xlint:all')
  end

  it 'should use -lint argument with value of option as array' do
    compile_task.using(:lint=>['path', 'serial'])
    javac_args.should include('-Xlint:path,serial')
  end

  it 'should not set other option by default' do
    compile_task.options.other.should be_nil
  end

  it 'should pass other argument if other option is string' do
    compile_task.using(:other=>'-Xprint')
    javac_args.should include('-Xprint')
  end

  it 'should pass other argument if other option is array' do
    compile_task.using(:other=>['-Xstdout', 'msgs'])
    javac_args.should include('-Xstdout', 'msgs')
  end

  it 'should complain about options it doesn\'t know' do
    write 'source/Test.java', 'class Test {}'
    compile_task.using(:unknown=>'option')
    lambda { compile_task.from('source').invoke }.should raise_error(ArgumentError, /no such option/i)
  end

  it 'should inherit options from parent' do
    define 'foo' do
      compile.using(:warnings=>true, :debug=>true, :deprecation=>true, :source=>'1.5', :target=>'1.4')
      define 'bar' do
        compile.using(:javac)
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
end
