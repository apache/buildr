require File.join(File.dirname(__FILE__), 'sandbox')


describe Buildr::CompileTask do
  before do
    # Test files to compile and target directory to compile into.
    @src_dir = 'src/java'
    @sources = ['Test1.java', 'Test2.java'].map { |f| File.join(@src_dir, f) }.
      each { |src| write src, "class #{src.pathmap('%n')} {}" }
    # You can supply a relative path, but a full path is used everywhere else.
    @target = File.expand_path('classes')
    @compile = define('foo').compile.using(:javac)
  end

  it 'should respond to from() and return self' do
    @compile.from(@sources).should be(@compile)
  end

  it 'should respond to from() and add sources' do
    @compile.from @sources, @src_dir
    @compile.sources.should eql(@sources + [@src_dir])
  end

  it 'should respond to with() and return self' do
    @compile.with('test.jar').should be(@compile)
  end

  it 'should respond to with() and add classpath dependencies' do
    jars = (1..3).map { |i| "test#{i}.jar" }
    @compile.with *jars
    @compile.classpath.should eql(artifacts(jars))
  end

  it 'should respond to into() and return self' do
    @compile.into(@target).should be(@compile)
  end

  it 'should respond to into() and create file task' do
    @compile.from(@sources).into(@target)
    lambda { file(@target).invoke }.should run_task('foo:compile')
  end

  it 'should respond to using() and return self' do
    @compile.using(:source=>'1.4').should eql(@compile)
  end

  it 'should respond to using() and set value options' do
    @compile.using(:source=>'1.4', 'target'=>'1.5')
    @compile.options.source.should eql('1.4')
    @compile.options.target.should eql('1.5')
  end

  it 'should compile only once' do
    @compile.from(@sources).into(@target)
    lambda { file(@target).invoke }.should run_task('foo:compile')
    lambda { @compile.invoke }.should_not run_task('foo:compile')
  end

  it 'should compile if there are source files to compile' do
    lambda { @compile.from(@sources).into(@target).invoke }.should run_task('foo:compile')
  end

  it 'should compile if directory has source files to compile' do
    lambda { @compile.from(@src_dir).into(@target).invoke }.should run_task('foo:compile')
  end

  it 'should timestamp target directory if specified' do
    time = Time.now - 10
    mkpath @target
    File.utime(time, time, @target)
    @compile.into(@target).timestamp.should be_close(time, 1)
  end
end


describe Buildr::CompileTask, 'compiler' do
  it 'should be nil if not identified' do
    define('foo').compile.compiler.should be_nil
  end
  
  it 'should be set by calling using' do
    define('foo') { compile.using(:javac) }
    project('foo').compile.compiler.should eql(:javac)
  end

  it 'should only support existing compiler' do
    lambda { define('foo') { compile.using(:unknown) } }.should raise_error(ArgumentError, /unknown compiler/i)
  end

  it 'should only allow setting the compiler once' do
    lambda { define('foo') { compile.using(:javac).using(:scalac) } }.should raise_error(RuntimeError, /already selected/i)
  end

  it 'should identify itself from source directories' do
    write 'src/main/java/Test.java', 'class Test {}' 
    define('foo').compile.compiler.should eql(:javac)
  end

  it 'should identify itself form project paths' do
    write 'bar/Test.java', 'class Test {}' 
    define('foo').compile.compiler.should be_nil
    define('bar') { compile.from 'bar' }.compile.compiler.should eql(:javac)
  end

  it 'should have no source/target mapping unless selected' do
    define('foo')
    project('foo').compile.sources.should be_empty
    project('foo').compile.target.should be_nil
  end

  it 'should set target directory' do
    define('foo') { compile.using(:javac) }
    project('foo').compile.sources.should be_empty
    project('foo').compile.target.to_s.should eql(File.expand_path('target/classes'))
  end

  it 'should not over-ride exisitng source and target directories' do
    define('foo') { compile.from('foo/java').into('classes').using(:javac) }
    project('foo').compile.sources.should eql(['foo/java'])
    project('foo').compile.target.to_s.should eql(File.expand_path('classes'))
  end

end


describe Buildr::CompileTask, 'sources' do
  before do
    @src_dir = 'src/java'
    @sources = ['Test1.java', 'Test2.java'].map { |f| File.join(@src_dir, f) }.
      each { |src| write src, "class #{src.pathmap('%n')} {}" }
    @compile = define('foo').compile.using(:javac)
    # Test files to compile and target directory to compile into.
  end

  it 'should be empty' do
    @compile.sources.should be_empty
  end

  it 'should be an array' do
    @compile.sources += @sources
    @compile.sources.should eql(@sources)
  end

  it 'should allow files' do
    @compile.from(@sources).into('classes').invoke
    @sources.each { |src| file(src.pathmap('classes/%n.class')).should exist }
  end

  it 'should allow directories' do
    @compile.from(@src_dir).into('classes').invoke
    @sources.each { |src| file(src.pathmap('classes/%n.class')).should exist }
  end

  it 'should require file or directory to exist' do
    lambda { @compile.from('empty').into('classes').invoke }.should raise_error(RuntimeError, /Don't know how to build/)
  end

  it 'should require at least one file to compile' do
    mkpath 'empty'
    lambda { @compile.from('empty').into('classes').invoke }.should_not run_task('foo:compile')
  end

  it 'should allow tasks' do
    lambda { @compile.from(file(@src_dir)).into('classes').invoke }.should run_task('foo:compile')
  end

  it 'should act as prerequisites' do
    file('src2') { |task| task('prereq').invoke ; mkpath task.name }
    lambda { @compile.from('src2').into('classes').invoke }.should run_task('prereq')
  end

  it 'should force compilation if no bytecode' do
    lambda { @compile.from(@sources).into(Dir.pwd).invoke }.should run_task('foo:compile')
  end

  it 'should force compilation if newer than bytecode' do
    # Simulate class files that are older than source files.
    time = Time.now
    @sources.each { |src| File.utime(time + 1, time + 1, src) }.
      map { |src| src.pathmap('%n').ext('.class') }.
      each { |kls| write kls ; File.utime(time, time, kls) }
    lambda { @compile.from(@sources).into(Dir.pwd).invoke }.should run_task('foo:compile')
  end

  it 'should not force compilation if older than bytecode' do
    # When everything has the same timestamp, nothing is compiled again.
    time = Time.now
    @sources.each { |src| File.utime(time, time, src) }.
      map { |src| src.pathmap('%n').ext('.class') }.
      each { |kls| write kls ; File.utime(time, time, kls) }
    lambda { @compile.from(@sources).into(Dir.pwd).invoke }.should_not run_task('foo:compile')
  end
end


describe Buildr::CompileTask, 'dependencies' do
  before do
    @compile = define('foo').compile.using(:javac)
    @sources = ['Test1.java', 'Test2.java'].
      each { |src| write src, "class #{src.pathmap('%n')} {}" }
    define('to_jar').compile.using(:javac).from(@sources).into(Dir.pwd).invoke
    @jars = [ 'test1.jar', 'test2.jar' ]. # javac can't cope with empty jars
     each { |jar| zip(jar).include(@sources.map { |src| src.ext('class') }).invoke }
  end

  it 'should be empty' do
    @compile.dependencies.should be_empty
  end

  it 'should be an array' do
    @compile.dependencies += @jars
    @compile.dependencies.should eql(@jars)
  end

  it 'should allow files' do
    @compile.from(@sources).with(@jars).into('classes').invoke
    @sources.each { |src| file(src.pathmap('classes/%n.class')).should exist }
  end

  it 'should allow tasks' do
    @compile.from(@sources).with(file(@jars.first)).into('classes').invoke
  end

  it 'should allow artifacts' do
    artifact('group:id:jar:1.0') { |task| mkpath File.dirname(task.to_s) ; cp @jars.first, task.to_s }
    @compile.from(@sources).with('group:id:jar:1.0').into('classes').invoke
  end

  it 'should allow projects' do
    define('bar', :version=>'1', :group=>'self') { package :jar }
    @compile.with project('bar')
    @compile.dependencies.should eql(project('bar').packages)
  end

  it 'should require file to exist' do
    lambda { @compile.from(@sources).with('no-such.jar').into('classes').invoke }.should \
      raise_error(RuntimeError, /Don't know how to build/)
  end

  it 'should act as prerequisites' do
    file(File.expand_path('no-such.jar')) { |task| task('prereq').invoke }
    lambda { @compile.from(@sources).with('no-such.jar').into('classes').invoke }.should run_tasks(['prereq', 'foo:compile'])
  end

  it 'should include as classpath dependency' do
    src = file('TestOfTest1.java') { |task| write task.to_s, 'class TestOfTest1 { Test1 _var; }' }
    lambda { @compile.from(src).with(@jars).into('classes').invoke }.should run_task('foo:compile')
  end

  it 'should force compilation if newer than bytecode' do
    # On my machine the times end up the same, so need to push sources in the past.
    @sources.each { |src| File.utime(Time.now - 10, Time.now - 10, src.ext('.class')) }
    lambda { @compile.from(@sources).with(@jars).into(Dir.pwd).invoke }.should run_task('foo:compile')
  end

  it 'should not force compilation if not newer than bytecode' do
    # Push sources/classes into the future so they're both newer than classpath, but not each other.
    @sources.map { |src| [src, src.ext('.class')] }.flatten.each { |f| File.utime(Time.now + 10, Time.now + 10, f) }
    lambda { @compile.from(@sources).with(@jars).into(Dir.pwd).invoke }.should_not run_task('foo:compile')
  end 

  it 'should be accessible as classpath' do
    lambda { @compile.classpath = @jars }.should change(@compile, :dependencies).to(@jars)
    lambda { @compile.dependencies = [] }.should change(@compile, :classpath).to([])
  end

end


describe Buildr::CompileTask, 'target' do
  before do
    @compile = define('foo').compile.using(:javac)
    write 'Test.java', 'class Test {}'
  end

  it 'should be a file task' do
    @compile.from('Test.java').into('classes')
    @compile.target.should be_kind_of(Rake::FileTask)
  end

  it 'should set to full path' do
    @compile.into('classes').target.to_s.should eql(File.expand_path('classes'))
  end

  it 'should accept a task' do
    task = file(File.expand_path('classes'))
    @compile.into(task).target.should be(task)
  end

  it 'should create dependency in file task when set' do
    @compile.from('Test.java').into('classes')
    lambda { file(File.expand_path('classes')).invoke }.should run_task('foo:compile')
  end

  it 'should exist after compilation' do
    lambda { @compile.from('Test.java').into('classes').invoke }.should run_task('foo:compile')
    FileList['classes/*'].should == ['classes/Test.class']
  end

  it 'should be touched if anything compiled' do
    mkpath 'classes' ; File.utime(Time.now - 100, Time.now - 100, 'classes')
    lambda { @compile.from('Test.java').into('classes').invoke }.should run_task('foo:compile')
    File.stat('classes').mtime.should be_close(Time.now, 2)
  end

  it 'should not be touched if failed to compile' do
    mkpath 'classes' ; File.utime(Time.now - 10, Time.now - 10, 'classes')
    Java.should_receive(:javac).and_raise
    lambda { @compile.from('Test.java').into('classes').invoke }.should raise_error
    File.stat('classes').mtime.should be_close(Time.now - 10, 2)
  end
end


=begin
describe Buildr::CompileTask, 'options' do
  before do
    @default = {:debug=>true, :deprecation=>false, :lint=>false, :warnings=>false, :other=>nil, :source=>nil, :target=>nil}
  end

  it 'should set warnings option to false by default' do
    define('foo').compile.options.warnings.should be_false
  end

  it 'should set wranings option to true when running with --verbose option' do
    verbose true
    define('foo').compile.options.warnings.should be_true
  end

  it 'should use -nowarn argument unless warnings is true' do
    define('foo').compile.using(:warnings=>true).javac_args.should_not include('-nowarn')
    define('bar').compile.using(:warnings=>false).javac_args.should include('-nowarn')
  end

  it 'should use -verbose argument only when running with --trace option' do
    define('foo').compile.javac_args.should_not include('-verbose')
    Rake.application.options.trace = true
    define('bar').compile.javac_args.should include('-verbose')
  end

  it 'should set debug option to true by default' do
    define('foo').compile.options.debug.should be_true
  end

  it 'should set debug option to false based on Buildr.options' do
    Buildr.options.debug = false
    define('foo').compile.options.debug.should be_false
  end

  it 'should set debug option to false based on debug environment variable' do
    ENV['debug'] = 'no'
    define('foo').compile.options.debug.should be_false
  end

  it 'should set debug option to false based on DEBUG environment variable' do
    ENV['DEBUG'] = 'no'
    define('foo').compile.options.debug.should be_false
  end

  it 'should use -g argument only when running in debug mode' do
    define('foo').compile.using(:debug=>true).javac_args.should include('-g')
    define('bar').compile.using(:debug=>false).javac_args.should_not include('-g')
  end

  it 'should set deprecation option to false by default' do
    define('foo').compile.options.deprecation.should be_false
  end

  it 'should use -deprecation argument if deprecation option set' do
    define('foo').compile.using(:deprecation=>true).javac_args.should include('-deprecation')
    define('bar').compile.using(:deprecation=>false).javac_args.should_not include('-deprecation')
  end

  it 'should not set source and target options by default' do
    define('foo').compile.options.source.should be_nil
    define('bar').compile.options.target.should be_nil
  end

  it 'should use -source nn argument if source option set' do
    define('foo').compile.javac_args.should_not include('-source')
    define('bar').compile.using(:source=>'1.5').javac_args.should include('-source', '1.5')
  end

  it 'should use -target nn argument if target option set' do
    define('foo').compile.javac_args.should_not include('-target')
    define('bar').compile.using(:target=>'1.5').javac_args.should include('-target', '1.5')
  end

  it 'should set lint option false by default' do
    define('foo').compile.options.lint.should be_false
  end

  it 'should use -Xlint argument based on lint option' do
    define('foo').compile.javac_args.should_not include('-Xlint')
    define('true').compile.using(:lint=>true).javac_args.should include('-Xlint')
    define('all').compile.using(:lint=>'all').javac_args.should include('-Xlint:all')
    define('select').compile.using(:lint=>['path', 'serial']).javac_args.should include('-Xlint:path,serial')
  end

  it 'should pass other option as remaining arguments' do
    define('none').compile.javac_args.should eql(['-nowarn', '-g'])
    define('one').compile.using(:other=>'-foo').javac_args.should include('-foo')
    define('array').compile.using(:other=>['-foo', '-bar']).javac_args.should include('-foo', '-bar')
    define('hash').compile.using(:other=>{ 'foo'=>'name', 'bar'=>'value'}).javac_args.should include('-foo', 'name', '-bar', 'value')
  end

  it 'should accept unknown option'
  it 'should complain about unknown option'


  it "should pass to javac" do
    src = "Test.java"
    write src, "class Test {}"
    Java.should_receive(:javac) do |*args|
      args.last[:javac_args].should include("-nowarn")
      args.last[:javac_args].join(" ").should include("-source 1.5")
    end
    CompileTask.define_task("compiling").from(src).into("classes").using(:source=>"1.5").invoke
  end

  after do
    Buildr.options.debug = nil
    ENV.delete "debug"
    ENV.delete "DEBUG"
  end
end
=end


def accessor_task_spec(name)
  it 'should be a task' do
    define 'foo'
    project('foo').send(name).should be_a_kind_of(Rake::Task)
  end

  it 'should always return the same task' do
    task = nil
    define('foo') { task = self.send(name) }
    project('foo').send(name).should be(task)
  end

  it 'should be unique for project' do
    define('foo') { define 'bar' }
    project('foo').send(name).should_not be(project('foo:bar').send(name))
  end

  it 'should have a project:#{name} name' do
    define('foo') { define 'bar' }
    project('foo').send(name).name.should eql("foo:#{name}")
    project('foo:bar').send(name).name.should eql("foo:bar:#{name}")
  end

end


describe Project, '#compile' do
  accessor_task_spec :compile

  def make_sources()
    write 'src/main/java/Test.java', 'class Test {}'
  end

  it 'should be a compile task' do
    define 'foo'
    project('foo').compile.should be_instance_of(CompileTask)
  end

  it 'should inherit options from parent' do
    define 'foo' do
      compile.options.source = '1.5'
      define 'bar'
    end
    project('foo:bar').compile.options.source = '1.5'
  end

  it 'should accept options independently of parent' do
    define 'foo' do
      compile.options.source = '1.5'
      define 'bar' do
        compile.options.source = '1.6'
      end
    end
    project('foo').compile.options.source = '1.4'
    project('foo:bar').compile.options.source = '1.5'
  end

  it 'should not inherit options from local task' do
    class << task('compile')
      def options ; fail ; end
    end
    lambda { define('foo') { compile.options } }.should_not raise_error
  end

  it 'should accept source files' do
    define('foo') { compile('file1', 'file2') }
    project('foo').compile.sources.should eql(['file1', 'file2'])
  end

  it 'should accept block' do
    make_sources
    task 'action'
    define('foo') { compile { task('action').invoke } }
    lambda { project('foo').compile.invoke }.should run_tasks(['foo:compile', 'action'])
  end

  it 'should set source directory to src/main/java' do
    make_sources
    define 'foo'
    project('foo').compile.sources.should include(File.expand_path('src/main/java'))  
  end

  it 'should not set source directory unless exists' do
    define 'foo'
    project('foo').compile.sources.should be_empty
  end

  it 'should set target directory to target/classes' do
    make_sources
    define 'foo'
    project('foo').compile.target.to_s.should eql(File.expand_path('target/classes'))
  end

  it 'should create file task for target directory' do
    make_sources
    define 'foo'
    file(File.expand_path('target/classes')).prerequisites.should include(project('foo').compile)
  end

  it 'should execute resources task if compiling' do
    write 'src/main/java/Test.java', 'class Test {}'
    write 'src/main/resources/resource', 'resource'
    define('foo') { resources }
    lambda { project('foo').compile.invoke }.should run_task('foo:resources')
  end

  it 'should always execute resources task' do
    define('foo') { resources }
    lambda { project('foo').compile.invoke }.should run_task('foo:resources')
  end

  it 'should be recursive' do
    write 'bar/src/main/java/Test.java', 'class Test {}'
    define('foo') { define('bar') { compile } }
    lambda { project('foo').compile.invoke }.should run_task('foo:bar:compile')
  end

  it 'should be a local task' do
    write 'src/main/java/Test.java', 'class Test {}'
    write 'bar/src/main/java/Test.java', 'class Test {}'
    define('foo') { define 'bar' }
    lambda { in_original_dir(project('foo:bar').base_dir) { task('compile').invoke } }.should run_task('foo:bar:compile').but_not('foo:compile')
  end

  it 'should execute from build' do
    write 'bar/src/main/java/Test.java', 'class Test {}'
    define('foo') { define('bar') { compile } }
    lambda { task('build').invoke }.should run_task('foo:bar:compile')
  end

  it 'should not copy files from src/main/java to target' do
    write 'src/main/java/Test.java', 'class Test {}'
    write 'src/main/java/properties', 'copy=yes'
    define('foo').task('build').invoke
    Dir.glob("#{project('foo').compile.target}/**/*").should eql([File.expand_path('target/classes/Test.class')])
  end

  it 'should clean after itself' do
    mkpath 'target'
    define 'foo'
    lambda { task('clean').invoke }.should change { File.exist?('target') }.to(false)
  end
end


describe Project, '#resources' do
  accessor_task_spec :resources

  def make_resources()
    @resources = [ 'resource1', 'resource2', '.config' ]
    @resources.each { |res| write "src/main/resources/#{res}", res }
  end

  it 'should provide a filter' do
    define 'foo'
    project('foo').resources.filter.should be_instance_of(Filter)
  end

  it 'should accept prerequisites' do
    tasks = ['task1', 'task2'].each { |name| task(name) }
    define('foo') { resources *tasks }
    lambda { project('foo').resources.invoke }.should run_tasks(*tasks)
  end

  it 'should accept block' do
    make_resources
    task 'action'
    define('foo') { resources { task('action').invoke } }
    lambda { project('foo').resources.invoke }.should run_task('action')
  end

  it 'should set target directory by default' do
    make_resources
    define 'foo'
    project('foo').resources.filter.target.to_s.should eql(project('foo').path_to('target/resources'))
  end

  it 'should use target directory if specified' do
    define 'foo' do
      compile.into 'the_classes'
      resources.filter.into 'the_resources'
    end
    project('foo').resources.filter.target.to_s.should eql(File.expand_path('the_resources'))
  end

  it 'should create file task for target directory' do
    make_resources
    task 'filtering'
    define('foo') do
      class << resources.filter
        def run() ; task('filtering').invoke ; end
      end
    end
    lambda { file(File.expand_path('target/resources')).invoke }.should run_task('filtering')
  end

  it 'should include all files in the resources directory' do
    make_resources
    define 'foo'
    project('foo').resources.invoke
    FileList['target/resources/{*,.*}'].reject { |f| File.directory?(f) }.map { |f| File.read(f) }.sort.should == @resources.sort
  end

  it 'should always execute resources task when compiling' do
    define('foo') { resources }
    lambda { project('foo').compile.invoke }.should run_task('foo:resources')
  end

  it 'should respond to from and add additional directories' do
    make_resources
    mkpath 'extra' ; write 'extra/special'
    define('foo') { resources.from 'extra' }
    project('foo').resources.invoke
    FileList['target/resources/{*,.*}'].should include(*@resources.map { |file| "target/resources/#{file}" })
    FileList['target/resources/{*,.*}'].should include('target/resources/special')
  end

  it 'should work with directories other than resources' do
    mkpath 'extra' ; write 'extra/special'
    define('foo') { resources.from 'extra' }
    project('foo').resources.invoke
    FileList['target/resources/**'].should include('target/resources/special')
  end

  it 'should use current profile for filtering'
end


describe Project, '#javadoc' do
  accessor_task_spec :javadoc

  def make_sources(dir = nil)
    @src_dir = (dir ? "#{dir}/" : '') + 'src/main/java/pkg'
    @sources = (1..3).map { |i| "Test#{i}" }.
      each { |name| write "#{@src_dir}/#{name}.java", "package pkg; public class #{name}{}" }.
      map { |name| File.expand_path("#{@src_dir}/#{name}.java") }
  end

  it 'should always set target directory' do
    define 'foo'
    project('foo').javadoc.target.should_not be_nil
  end

  it 'should set target directory to target/javadoc' do
    define 'foo'
    project('foo').javadoc.target.to_s.should eql(File.expand_path('target/javadoc'))
  end

  it 'should create file task for target directory' do
    define 'foo'
    file(File.expand_path('target/javadoc')).prerequisites.should include(project('foo').javadoc)
  end

  it 'should respond to into() and return self' do
    task = nil
    define('foo') { task = javadoc.into('docs') }
    task.should be(project('foo').javadoc)
  end

  it 'should respond to into() and change target' do
    define('foo') { javadoc.into('docs') }
    project('foo').javadoc.target.to_s.should eql(File.expand_path('docs'))
    file(File.expand_path('docs')).prerequisites.should include(project('foo').javadoc)
  end

  it 'should respond to from() and return self' do
    task = nil
    define('foo') { task = javadoc.from('srcs') }
    task.should be(project('foo').javadoc)
  end

  it 'should respond to from() and add source file' do
    define('foo') { javadoc.from 'srcs' }
    project('foo').javadoc.source_files.should include('srcs')
  end

  it 'should respond to from() and add file task' do
    define('foo') { javadoc.from file('srcs') }
    project('foo').javadoc.source_files.should include(File.expand_path('srcs'))
  end

  it 'should generate javadocs from project' do
    make_sources
    define 'foo'
    project('foo').javadoc.source_files.sort.should == @sources.sort
  end

  it 'should generate javadocs from project using its classpath' do
    make_sources
    define('foo') { compile.with 'group:id:jar:1.0' }
    project('foo').javadoc.classpath.map(&:to_spec).should eql(['group:id:jar:1.0'])
  end

  it 'should respond to from() and add compile sources and dependencies' do
    make_sources 'bar'
    define 'foo' do
      define('bar') { compile.with 'group:id:jar:1.0' }
      javadoc.from project('foo:bar')
    end
    project('foo').javadoc.source_files.sort.should == @sources.sort
    project('foo').javadoc.classpath.map(&:to_spec).should eql(['group:id:jar:1.0'])
  end

  it 'should respond to include() and return self' do
    define('foo') { javadoc.include('srcs').should be(javadoc) }
  end

  it 'should respond to include() and add files' do
    make_sources 'bar'
    define 'foo'
    project('foo').javadoc.include @sources.first
    project('foo').javadoc.source_files.sort.should == [@sources.first]
  end

  it 'should respond to exclude() and return self' do
    define('foo') { javadoc.exclude('srcs').should be(javadoc) }
  end

  it 'should respond to exclude() and ignore files' do
    make_sources
    define 'foo'
    project('foo').javadoc.exclude @sources.first
    project('foo').javadoc.source_files.sort.should == @sources[1..-1]
  end

  it 'should respond to using() and return self' do
    define('foo') { javadoc.using(:windowtitle=>'Fooing').should be(javadoc) }
  end

  it 'should respond to using() and accept options' do
    define('foo') { javadoc.using :windowtitle=>'Fooing' }
    project('foo').javadoc.options[:windowtitle].should eql('Fooing')
  end

  it 'should pick -windowtitle from project name' do
    define('foo') { define 'bar' }
    project('foo').javadoc.options[:windowtitle].should eql('foo')
    project('foo:bar').javadoc.options[:windowtitle].should eql('foo:bar')
  end

  it 'should pick -windowtitle from project description' do
    desc 'My App'
    define 'foo'
    project('foo').javadoc.options[:windowtitle].should eql('My App')
  end

  it 'should produce documentation' do
    make_sources
    define 'foo'
    suppress_stdout { project('foo').javadoc.invoke }
    (1..3).map { |i| "target/javadoc/pkg/Test#{i}.html" }.each { |f| file(f).should exist }
  end

  it 'should fail on error' do
    write 'Test.java', 'class Test {}'
    define('foo') { javadoc.include 'Test.java' }
    suppress_stdout do
      lambda { project('foo').javadoc.invoke }.should raise_error(RuntimeError, /Failed to generate Javadocs/)
    end
  end

  it 'should be local task' do
    make_sources
    make_sources 'bar'
    define('foo') { define 'bar' }
    lambda { in_original_dir project('foo:bar').base_dir do
      suppress_stdout { task('javadoc').invoke }
    end }.should run_task('foo:bar:javadoc').but_not('foo:javadoc')
  end

  it 'should not recurse' do
    make_sources
    make_sources 'bar'
    define('foo') { define 'bar' }
    lambda { suppress_stdout { task('javadoc').invoke } }.should run_task('foo:javadoc').but_not('foo:bar:javadoc')
  end

  it 'should include prerequisites from compile task'
end
