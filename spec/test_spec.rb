require File.join(File.dirname(__FILE__), 'sandbox')


describe Buildr::TestTask do
  it "should respond to :compile and return compile task" do
    define "foo" do
      test.compile.should be(task("test:compile"))
      test.compile.should be_kind_of(Buildr::CompileTask)
    end
  end

  it "should respond to :compile and add sources to test:compile" do
    define("foo") { test.compile "prereq" }
    project("foo").task("test:compile").sources.should include("prereq")
  end

  it "should respond to :compile and add action for test:compile" do
    write "src/test/java/Test.java", "class Test {}"
    task "action"
    define("foo") { test.compile { task("action").invoke } }
    lambda { project("foo").test.compile.invoke }.should run_tasks("action")
  end

  it "should respond to :resources and return resources task" do
    define "foo" do
      test.resources.should be(task("test:resources"))
      test.resources.should be_kind_of(Buildr::ResourcesTask)
    end
  end

  it "should respond to :resources and add prerequisites to test:resources" do
    define("foo") { test.resources "prereq" }
    project("foo").task("test:resources").prerequisites.should include("prereq")
  end

  it "should respond to :resources and add action for test:resources" do
    task "action"
    define("foo") { test.resources { task("action").invoke } }
    lambda { project("foo").test.resources.invoke }.should run_tasks("action")
  end

  it "should respond to :setup and return setup task" do
    define("foo") { test.setup.should be(task("test:setup")) }
  end

  it "should respond to :setup and add prerequisites to test:setup" do
    define("foo") { test.setup "prereq" }
    project("foo").task("test:setup").prerequisites.should include("prereq")
  end

  it "should respond to :setup and add action for test:setup" do
    task "action"
    define("foo") { test.setup { task("action").invoke } }
    lambda { project("foo").test.setup.invoke }.should run_tasks("action")
  end

  it "should respond to :teardown and return teardown task" do
    define("foo") { test.teardown.should be(task("test:teardown")) }
  end

  it "should respond to :teardown and add prerequisites to test:teardown" do
    define("foo") { test.teardown "prereq" }
    project("foo").task("test:teardown").prerequisites.should include("prereq")
  end

  it "should respond to :teardown and add action for test:teardown" do
    task "action"
    define("foo") { test.teardown { task("action").invoke } }
    lambda { project("foo").test.teardown.invoke }.should run_tasks("action")
  end

  it "should respond to :with and return self" do
    define("foo") { test.with.should be(test) }
  end

  it "should respond to :with and add artifacfs to compile task dependencies" do
    define("foo") { test.with "test.jar", "acme:example:jar:1.0" }
    project("foo").test.compile.dependencies.should include(File.expand_path("test.jar"))
    project("foo").test.compile.dependencies.should include(artifact("acme:example:jar:1.0"))
  end

  it "should respond to :with and add artifacfs to task dependencies" do
    define("foo") { test.with "test.jar", "acme:example:jar:1.0" }
    project("foo").test.dependencies.should include(File.expand_path("test.jar"))
    project("foo").test.dependencies.should include(artifact("acme:example:jar:1.0"))
  end

  it "should respond to :using and return self" do
    define("foo") { test.using.should be(test) }
  end

  it "should respond to :using and set value options" do
    define("foo") { test.using("foo"=>"FOO", "bar"=>"BAR").should be(test) }
    project("foo").test.options[:foo].should eql("FOO")
    project("foo").test.options[:bar].should eql("BAR")
  end

  it "should respond to :using and set symbol options" do
    define("foo") { test.using(:foo, :bar).should be(test) }
    project("foo").test.options[:foo].should be_true
    project("foo").test.options[:bar].should be_true
  end

  it "should respond to :include and return self" do
    define("foo") { test.include.should be(test) }
  end

  it "should respond to :include and add inclusion patterns" do
    define("foo") { test.include "Foo", "Bar" }
    project("foo").test.send(:include?, "Foo").should be_true
    project("foo").test.send(:include?, "Bar").should be_true
  end

  it "should respond to :exclude and return self" do
    define("foo") { test.exclude.should be(test) }
  end

  it "should respond to :exclude and add exclusion patterns" do
    define("foo") { test.exclude "FooTest", "BarTest" }
    project("foo").test.send(:include?, "FooTest").should be_false
    project("foo").test.send(:include?, "BarTest").should be_false
    project("foo").test.send(:include?, "BazTest").should be_true
  end

  it "should use JUnit test framework by default" do
    define "foo"
    project("foo").test.framework.should eql(:junit)
  end

  it "should support switching to TestNG framework" do
    define("foo") { test.using :testng }
    project("foo").test.framework.should eql(:testng)
  end

  it "should use the compile dependencies" do
    define("foo") { compile.with "group:id:jar:1.0" }
    project("foo").test.dependencies.should include(artifact("group:id:jar:1.0"))
  end

  it "should include the compile target in its dependencies" do
    define("foo") { compile.using(:javac) }
    project("foo").test.dependencies.should include(project("foo").compile.target)
  end

  it "should clean after itself (test files)" do
    define("foo") { test.compile.using(:javac) }
    mkpath project("foo").test.compile.target.to_s
    lambda { task("clean").invoke }.should change { File.exist?(project("foo").test.compile.target.to_s) }.to(false)
  end

  it "should clean after itself (reports)" do
    define "foo"
    mkpath project("foo").test.report_to.to_s
    lambda { task("clean").invoke }.should change { File.exist?(project("foo").test.report_to.to_s) }.to(false)
  end

end


describe Buildr::TestTask, " with no tests" do
  before do
    define "foo"
  end

  it "should pass" do
    lambda { project("foo").test.invoke }.should_not raise_error
  end

  it "should report no failed tests" do
    project("foo").test.invoke
    project("foo").test.failed_tests.should be_empty
  end
  
  it "should report no passed tests" do
    project("foo").test.invoke
    project("foo").test.files.should be_empty
  end

  it "should execute teardown task" do
    lambda { project("foo").test.invoke }.should run_task("foo:test:teardown")
  end
end


describe Buildr::TestTask, " with passing tests" do
  before do
    @tests = ["PassingTest1", "PassingTest2"]
    define "foo"
    project("foo").test.stub!(:files).and_return @tests
    project("foo").test.stub!(:junit_run).and_return []
  end

  it "should pass" do
    lambda { project("foo").test.invoke }.should_not raise_error
  end

  it "should report no failed tests" do
    project("foo").test.invoke
    project("foo").test.failed_tests.should be_empty
  end

  it "should fail if only one test fails" do
    TestFramework.frameworks[:junit].stub!(:run).and_return [@tests.last]
    lambda { project("foo").test.invoke }.should raise_error(RuntimeError, /Tests failed/)
  end

  it "should execute teardown task" do
    lambda { project("foo").test.invoke }.should run_task("foo:test:teardown")
  end
end


describe Buildr::TestTask, " with failed test" do
  before do
    @tests = ["FailingTest1", "FailingTest2"]
    define "foo"
    project("foo").test.stub!(:files).and_return @tests
    TestFramework.frameworks[:junit].stub!(:run).and_return @tests
  end

  it "should fail" do
    lambda { project("foo").test.invoke }.should raise_error(RuntimeError, /Tests failed/)
  end

  it "should report failed tests" do
    lambda { verbose(true) { project("foo").test.invoke rescue nil } }.should warn_that(/FailingTest/)
    project("foo").test.failed_tests.should == @tests
  end

  it "should warn but not fail if fail_on_failure is false" do
    project("foo").test.using :fail_on_failure=>false
    lambda { lambda { verbose(true) { project("foo").test.invoke } }.should_not raise_error }.should warn_that(/FailingTest/)
    project("foo").test.failed_tests.should == @tests
  end

  it "should execute teardown task" do
    lambda { project("foo").test.invoke rescue nil }.should run_task("foo:test:teardown")
  end
end


describe Buildr::TestFramework::JUnit do
  before do
    write "src/test/java/PassingTest.java", 
      "public class PassingTest extends junit.framework.TestCase { public void testNothing() {} }"
    write "src/test/java/FailingTest.java", 
      "public class FailingTest extends junit.framework.TestCase { public void testNothing() { assertTrue(false); } }"
    define "foo"
  end

  it "should include JUnit requirements" do
    project("foo").test.requires.should include(*TestFramework::JUnit::JUNIT_REQUIRES)
    project("foo").test.compile.dependencies.should include(*artifacts(TestFramework::JUnit::JUNIT_REQUIRES))
    project("foo").test.dependencies.should include(*artifacts(TestFramework::JUnit::JUNIT_REQUIRES))
  end

  it "should include JMock requirements" do
    project("foo").test.requires.should include(*TestFramework::JMock::JMOCK_REQUIRES)
    project("foo").test.compile.dependencies.should include(*artifacts(TestFramework::JMock::JMOCK_REQUIRES))
    project("foo").test.dependencies.should include(*artifacts(TestFramework::JMock::JMOCK_REQUIRES))
  end

  it "should include classes starting with and ending with Test" do
    ["TestThis", "ThisTest", "ThisThat"].each do |name|
      write "target/test/classes/#{name}.class"
    end
    project("foo").test.files.map { |file| File.basename(file) }.should == ["TestThis.class", "ThisTest.class"]
  end

  it "should ignore inner classes" do
    ["TestThis", "TestThis$Innner"].each do |name|
      write "target/test/classes/#{name}.class"
    end
    project("foo").test.files.map { |file| File.basename(file) }.should == ["TestThis.class"]
  end

  it "should pass when JUnit test case passes" do
    project("foo").test.include "PassingTest"
    lambda { project("foo").test.invoke }.should_not raise_error
  end

  it "should fail when JUnit test case fails" do
    project("foo").test.include "FailingTest"
    lambda { project("foo").test.invoke }.should raise_error(RuntimeError, /Tests failed/)
  end

  it 'should report failed test names' do
    project("foo").test.include "FailingTest"
    project("foo").test.invoke rescue
    project("foo").test.failed_tests.should eql(['FailingTest'])
  end

  it "should report to reports/junit" do
    project("foo").test.report_to.should be(project("foo").file("reports/junit"))
    project("foo").test.include("PassingTest").invoke
    project("foo").file("reports/junit/TEST-PassingTest.txt").should exist
    project("foo").file("reports/junit/TEST-PassingTest.xml").should exist
  end

  it "should pass properties to JVM" do
    write "src/test/java/PropertyTest.java", <<-JAVA
      public class PropertyTest extends junit.framework.TestCase {
        public void testProperty() {
          assertEquals("value", System.getProperty("name"));
        }
      }
    JAVA
    project("foo").test.include "PropertyTest"
    project("foo").test.using :properties=>{ 'name'=>'value' }
    project("foo").test.invoke
  end

  it "should set current directory" do
    mkpath "baz"
    write "baz/src/test/java/CurrentDirectoryTest.java", <<-JAVA
      public class CurrentDirectoryTest extends junit.framework.TestCase {
        public void testCurrentDirectory() throws Exception {
          assertEquals("#{File.expand_path('baz')}", new java.io.File(".").getCanonicalPath());
        }
      }
    JAVA
    define "bar" do
      define "baz" do
        test.include "CurrentDirectoryTest"
      end
    end
    project("bar:baz").test.invoke
  end
end


describe Buildr::TestTask, " using testng" do
  before do
    write "src/test/java/PassingTest.java", 
      "public class PassingTest { @org.testng.annotations.Test public void testNothing() {} }"
    write "src/test/java/FailingTest.java", 
      "public class FailingTest { @org.testng.annotations.Test public void testNothing() { org.testng.AssertJUnit.assertTrue(false); } }"
    define("foo") { test.using :testng }
  end

  it "should include TestNG requirements" do
    project("foo").test.requires.should include(*TestFramework::TestNG::TESTNG_REQUIRES)
    project("foo").test.compile.dependencies.should include(*artifacts(TestFramework::TestNG::TESTNG_REQUIRES))
    project("foo").test.dependencies.should include(*artifacts(TestFramework::TestNG::TESTNG_REQUIRES))
  end

  it "should include TestNG requirements" do
    project("foo").test.requires.should include(*TestFramework::JMock::JMOCK_REQUIRES)
    project("foo").test.compile.dependencies.should include(*artifacts(TestFramework::JMock::JMOCK_REQUIRES))
    project("foo").test.dependencies.should include(*artifacts(TestFramework::JMock::JMOCK_REQUIRES))
  end

  it "should include classes starting with and ending with Test" do
    ["TestThis", "ThisTest", "ThisThat"].each do |name|
      write File.join(project("foo").test.compile.target.to_s, name).ext("class")
    end
    project("foo").test.files.map { |file| File.basename(file) }.should == ["TestThis.class", "ThisTest.class"]
  end

  it "should ignore inner classes" do
    ["TestThis", "TestThis$Innner"].each do |name|
      write "target/test/classes/#{name}.class"
    end
    project("foo").test.files.map { |file| File.basename(file) }.should == ["TestThis.class"]
  end

  it "should pass when TestNG test case passes" do
    project("foo").test.include "PassingTest"
    lambda { project("foo").test.invoke }.should_not raise_error
  end

  it "should fail when TestNG test case fails" do
    project("foo").test.include "FailingTest"
    lambda { project("foo").test.invoke }.should raise_error(RuntimeError, /Tests failed/)
  end

  it 'should report failed test names' do
    project("foo").test.include "FailingTest"
    project("foo").test.invoke rescue
    project("foo").test.failed_tests.should eql(['FailingTest'])
  end

  it "should report to reports/testng" do
    project("foo").test.report_to.should be(project("foo").file("reports/testng"))
  end

  it "should generate reports" do
    project("foo").test.include "PassingTest"
    lambda { project("foo").test.invoke }.should change { File.exist?(project("foo").test.report_to.to_s) }.to(true)
  end
end



describe Buildr::Project.method(:test) do
  it "should return the project's test task" do
    define("foo") { test.should be(task("test")) }
  end

  it "should accept prerequisites for task" do
    define("foo") { test "prereq" }
    project("foo").test.prerequisites.should include("prereq")
  end

  it "should accept actions for task" do
    task "action"
    define("foo") { test { task("action").invoke } }
    lambda { project("foo").test.invoke }.should run_tasks("action")
  end

  it "should set fail_on_failure by default" do
    define("foo") { test.options[:fail_on_failure].should be_true }
  end

  it "should set fork mode by default" do
    define("foo") { test.options[:fork].should == :once }
  end

  it "should set no properties by default" do
    define("foo") { test.options[:properties].should be_empty }
  end

  it "should set no environment variables by default" do
    define("foo") { test.options[:environment].should be_empty }
  end

  it "should inherit options from parent project" do
    define "foo" do
      test.using :fail_on_failure=>false, :fork=>:each, :other=>"hello"
      define "bar" do
        test.options[:fail_on_failure].should be_false
        test.options[:fork].should == :each
        test.options[:other].should == "hello"
      end
    end
  end

  it "should clone options from parent project" do
    define "foo" do
      define "bar" do
        test.using :fail_on_failure=>false, :fork=>:each, :other=>"hello"
      end.invoke
      test.options[:fail_on_failure].should be_true
      test.options[:fork].should == :once
      test.options[:other].should be_nil
    end
  end

  it "should not inherit options from local test task" do
    class << task("test")
      def options ; fail ; end
    end
    lambda { define("foo") { test.options } }.should_not raise_error
  end
end


describe Rake::Task, "test" do
  it "should execute the compile task" do
    write "src/test/java/Nothing.java", "class Nothing {}"
    define "foo"
    lambda { project("foo").test.invoke }.should run_tasks("foo:test:compile")
  end

  it "should execute the setup task after the compile task" do
    write "src/test/java/Nothing.java", "class Nothing {}"
    define "foo"
    lambda { project("foo").test.invoke }.should run_tasks(["foo:test:compile", "foo:test:setup"])
  end

  it "should execute all other actions after the setup task" do
    define "foo" do
      task "enhanced"
      test { task("enhanced").invoke }
    end
    lambda { project("foo").test.invoke }.should run_tasks(["foo:test:setup", "foo:enhanced"])
  end

  it "should execute the teardown task after all actions" do
    define "foo" do
      task "enhanced"
      test { task("enhanced").invoke }
    end
    lambda { project("foo").test.invoke }.should run_tasks(["foo:enhanced", "foo:test:teardown"])
  end

  it "should be recursive" do
    define("foo") { define "bar" }
    lambda { task("test").invoke }.should run_tasks("foo:test", "foo:bar:test")
  end

  it "should not execute teardown if setup task failed" do
    define("foo") { test.setup { fail } }
    lambda { project("foo").test.invoke rescue nil }.should_not run_task("foo:test:teardown")
  end
end


describe Buildr::Project, "test:compile" do
  it "should execute project's compile task first" do
    write "src/main/java/Nothing.java", "class Nothing {}"
    write "src/test/java/Test.java", "class Test {}"
    define "foo"
    lambda { project("foo").test.compile.invoke }.should run_tasks(["foo:compile", "foo:test:compile"])
  end

  it "should pick sources from src/test/java if found" do
    mkpath "src/test/java"
    define("foo") do
      test.compile.using(:javac)
      test.compile.sources.should eql([_("src/test/java")])
    end
  end

  it "should ignore sources unless they exist" do
    define("foo") { test.compile.sources.should be_empty }
  end

  it "should compile to :target/test/classes" do
    define("foo", :target=>"targeted") do
      test.compile.using(:javac)
      test.compile.target.should eql(file("targeted/test/classes"))
    end
  end

  it "should use compile dependencies" do
    define("foo") { compile.with "group:id:jar:1.0" }
    project("foo").test.compile.dependencies.should include(artifact("group:id:jar:1.0"))
  end

  it "should include the compiled target in its dependencies" do
    define("foo") { compile.into "odd" }
    project("foo").test.compile.dependencies.should include(project("foo").file("odd"))
  end

  it "should include the test framework artifacts in its dependencies" do
    define "foo"
    project("foo").test.compile.dependencies.select { |path| path.respond_to?(:to_spec) }.map(&:to_spec).tap do |specs|
      project("foo").test.requires.each { |spec| specs.should include(spec) }
    end
  end

  it "should clean after itself" do
    write "src/test/java/Nothing.java", "class Nothing {}"
    define("foo") { test.compile.into "test-compiled" }
    project("foo").test.compile.invoke
    lambda { project("foo").clean.invoke }.should change { File.exist?("test-compiled") }.to(false)
  end
end


describe Buildr::Project, "test:resources" do
  it "should pick resources from src/test/resources if found" do
    mkpath "src/test/resources"
    define("foo") { test.resources.sources.should eql([file("src/test/resources")]) }
  end

  it "should ignore resources unless they exist" do
    define("foo") { test.resources.sources.should be_empty }
  end

  it "should copy to the resources target directory" do
    define("foo", :target=>"targeted") { test.resources.target.should eql(file("targeted/test/resources")) }
  end

  it "should execute alongside compile task" do
    task "action"
    define("foo") { test.resources { task("action").invoke } }
    lambda { project("foo").task("test:compile").invoke }.should run_tasks("action")
  end
end


describe Rake::Task, "test" do
  it "should be local task" do
    define "foo"
    define "bar", :base_dir=>"bar"
    lambda { task("test").invoke }.should run_task("foo:test").but_not("bar:test")
  end

  it "should stop at first failure" do
    define("foo") { test { fail } }
    define("bar") { test { fail } }
    lambda { task("test").invoke rescue nil }.should run_tasks("bar:test").but_not("foo:test")
  end

  it "should ignore failure if options.test is :all" do
    define("foo") { test { fail } }
    define("bar") { test { fail } }
    options.test = :all 
    lambda { task("test").invoke rescue nil }.should run_tasks("foo:test", "bar:test")
  end

  it "should ignore failure if options.test is :all" do
    define("foo") { test { fail } }
    define("bar") { test { fail } }
    ENV["test"] = "all"
    lambda { task("test").invoke rescue nil }.should run_tasks("foo:test", "bar:test")
  end
end

describe "test rule" do
  before do
    define("foo") { define "bar" }
  end

  it "should execute test task on local project" do
    lambda { task("test:something").invoke }.should run_task("foo:test")
  end

  it "should reset tasks to specific pattern" do
    task("test:something").invoke
    ["foo", "foo:bar"].map { |name| project(name) }.each do |project|
      project.test.include?("something").should be_true
      project.test.include?("nothing").should be_false
      project.test.include?("SomeTest").should be_false
    end
  end

  it "should apply *name* pattern" do
    task("test:something").invoke
    project("foo").test.include?("prefix-something-suffix").should be_true
    project("foo").test.include?("prefix-nothing-suffix").should be_false
  end

  it "should not apply *name* pattern if asterisks used" do
    task("test:*something").invoke
    project("foo").test.include?("prefix-something").should be_true
    project("foo").test.include?("prefix-something-suffix").should be_false
  end

  it "should accept multiple tasks separated by commas" do
    task("test:foo,bar").invoke
    project("foo").test.include?("foo").should be_true
    project("foo").test.include?("bar").should be_true
    project("foo").test.include?("baz").should be_false
  end

  it "should execute only the named tasts" do
    write "src/test/java/TestSomething.java",
      "public class TestSomething extends junit.framework.TestCase { public void testNothing() {} }"
    write "src/test/java/TestFails.java", "class TestFails {}"
    task("test:Something").invoke
  end
end


describe Rake::Task, "build" do
  it "should include test task if test option is on" do
    Buildr.options.test = true
    lambda { task("build").invoke }.should run_tasks("test")
  end

  it "should include test task if test option is on" do
    Buildr.options.test = false
    lambda { task("build").invoke }.should_not run_task("test")
  end
end


describe Buildr::Options, "test" do
  it "should be true by default" do
    Buildr.options.test.should be_true
  end

  ["skip", "no", "off", "false"].each do |value|
    it "should be false if test environment variable is '#{value}'" do
      lambda { ENV["test"] = value }.should change { Buildr.options.test }.to(false)
    end
  end

  ["skip", "no", "off", "false"].each do |value|
    it "should be false if TEST environment variable is '#{value}'" do
      lambda { ENV["TEST"] = value }.should change { Buildr.options.test }.to(false)
    end
  end

  it "should be :all if test environment variable is all" do
    lambda { ENV["test"] = "all" }.should change { Buildr.options.test }.to(:all)
  end

  it "should be :all if TEST environment variable is all" do
    lambda { ENV["TEST"] = "all" }.should change { Buildr.options.test }.to(:all)
  end

  it "should be true and warn for any other value" do
    ENV["TEST"] = "funky"
    lambda { Buildr.options.test.should be(true) }.should warn_that(/expecting the environment variable/i)
  end
end


describe Rake::Task, "junit:report" do

  it "should default to the target directory reports/junit" do
    TestFramework::JUnit.report.target.should eql("reports/junit")
  end

  it "should generate report into the target directory" do
    TestFramework::JUnit.report.target = "test-report"
    lambda { task("junit:report").invoke }.should change { File.exist?(TestFramework::JUnit.report.target) }.to(true)
  end

  it "should clean after itself" do
    mkpath TestFramework::JUnit.report.target
    lambda { task("clean").invoke }.should change { File.exist?(TestFramework::JUnit.report.target) }.to(false)
  end

  it "should generate a consolidated XML report" do
    lambda { task("junit:report").invoke }.should change { File.exist?("reports/junit/TESTS-TestSuites.xml") }.to(true)
  end

  it "should default to generating a report with frames" do
    TestFramework::JUnit.report.frames.should be_true
  end

  it "should generate single page when frames is false" do
    TestFramework::JUnit.report.frames = false
    task("junit:report").invoke
    file("reports/junit/html/junit-noframes.html").should exist
  end

  it "should generate frame page when frames is false" do
    TestFramework::JUnit.report.frames = true
    task("junit:report").invoke
    file("reports/junit/html/index.html").should exist
  end

  it "should generate reports from all projects that ran test cases" do
    write "src/test/java/TestSomething.java",
      "public class TestSomething extends junit.framework.TestCase { public void testNothing() {} }"
    define "foo"
    project("foo").test.invoke
    task("junit:report").invoke
    FileList["reports/junit/html/*TestSomething.html"].size.should be(1)
  end

  after do
    TestFramework::JUnit.instance_eval { @report = nil }
  end
end


describe Buildr, 'integration' do
  it 'should return the same task from all contexts' do
    task = task('integration')
    define 'foo' do
      integration.should be(task)
      define 'bar' do
        integration.should be(task)
      end
    end
    integration.should be(task)
  end

  it 'should respond to :setup and return setup task' do
    setup = integration.setup
    define('foo') { integration.setup.should be(setup) }
  end

  it 'should respond to :setup and add prerequisites to integration:setup' do
    define('foo') { integration.setup 'prereq' }
    integration.setup.prerequisites.should include('prereq')
  end

  it 'should respond to :setup and add action for integration:setup' do
    action = task('action')
    define('foo') { integration.setup { action.invoke } }
    lambda { integration.setup.invoke }.should run_tasks(action)
  end

  it 'should respond to :teardown and return teardown task' do
    teardown = integration.teardown
    define('foo') { integration.teardown.should be(teardown) }
  end

  it 'should respond to :teardown and add prerequisites to integration:teardown' do
    define('foo') { integration.teardown 'prereq' }
    integration.teardown.prerequisites.should include('prereq')
  end

  it 'should respond to :teardown and add action for integration:teardown' do
    action = task('action')
    define('foo') { integration.teardown { action.invoke } }
    lambda { integration.teardown.invoke }.should run_tasks(action)
  end
end


describe Rake::Task, 'integration' do
  it 'should be a local task' do
    define('foo') { test.using :integration }
    define('bar', :base_dir=>'other') { test.using :integration }
    lambda { task('integration').invoke }.should run_task('foo:test').but_not('bar:test')
  end

  it 'should be a recursive task' do
    define 'foo' do
      test.using :integration
      define('bar') { test.using :integration }
    end
    lambda { task('integration').invoke }.should run_tasks('foo:test', 'foo:bar:test')
  end

  it 'should find nested integration tests' do
    define 'foo' do
      define('bar') { test.using :integration }
    end
    lambda { task('integration').invoke }.should run_tasks('foo:bar:test').but_not('foo:test')
  end

  it 'should ignore nested regular tasks' do
    define 'foo' do
      test.using :integration
      define('bar') { test.using :integration=>false }
    end
    lambda { task('integration').invoke }.should run_tasks('foo:test').but_not('foo:bar:test')
  end

  it 'should agree not to run the same tasks as test' do
    define 'foo' do
      define 'bar' do
        test.using :integration
        define('baz') { test.using :integration=>false }
      end
    end
    lambda { task('test').invoke }.should run_tasks('foo:test', 'foo:bar:baz:test').but_not('foo:bar:test')
    lambda { task('integration').invoke }.should run_tasks('foo:bar:test').but_not('foo:test', 'foo:bar:baz:test')
  end

  it 'should run setup task before any project integration tests' do
    define('foo') { test.using :integration }
    define('bar') { test.using :integration }
    lambda { task('integration').invoke }.should run_tasks([integration.setup, 'bar:test', 'foo:test'])
  end

  it 'should run teardown task after all project integrations tests' do
    define('foo') { test.using :integration }
    define('bar') { test.using :integration }
    lambda { task('integration').invoke }.should run_tasks(['bar:test', 'foo:test', integration.teardown])
  end

  it 'should run test cases marked for integration' do
    write 'src/test/java/FailingTest.java', 
      'public class FailingTest extends junit.framework.TestCase { public void testNothing() { assertTrue(false); } }'
    define('foo') { test.using :integration }
    lambda { task('test').invoke }.should_not raise_error
    lambda { task('integration').invoke }.should raise_error(RuntimeError, /tests failed/i)
  end

  it 'should run setup and teardown tasks marked for integration' do
    define('foo') { test.using :integration }
    lambda { task('test').invoke }.should run_tasks().but_not('foo:test:setup', 'foo:test:teardown')
    lambda { task('integration').invoke }.should run_tasks('foo:test:setup', 'foo:test:teardown')
  end

  it 'should run test actions marked for integration' do
    task 'action'
    define 'foo' do
      test.using :integration
      test { task('action').invoke }
    end
    lambda { task('test').invoke }.should run_tasks().but_not('action')
    lambda { task('integration').invoke }.should run_task('action')
  end

  it 'should not fail if test=all' do
    write 'src/test/java/FailingTest.java', 
      'public class FailingTest extends junit.framework.TestCase { public void testNothing() { assertTrue(false); } }'
    define('foo') { test.using :integration }
    options.test = :all
    lambda { task('integration').invoke }.should_not raise_error
  end

  it 'should execute by local package task' do
    define 'foo', :version=>'1.0' do
      test.using :integration
      package :jar
    end
    lambda { task('package').invoke }.should run_tasks(['foo:package', 'foo:test'])
  end

  it 'should execute by local package task along with unit tests' do
    define 'foo', :version=>'1.0' do
      test.using :integration
      package :jar
      define('bar') { test.using :integration=>false }
    end
    lambda { task('package').invoke }.should run_tasks(['foo:package', 'foo:test'],
      ['foo:bar:build', 'foo:bar:test', 'foo:bar:package'])
  end

  it 'should not execute by local package task if test=no' do
    define 'foo', :version=>'1.0' do
      test.using :integration
      package :jar
    end
    options.test = false
    lambda { task('package').invoke }.should run_task('foo:package').but_not('foo:test')
  end
end


describe 'integration rule' do
  before do
    define 'foo' do
      test.using :integration
      define 'bar'
    end
  end

  it 'should execute integration tests on local project' do
    lambda { task('integration:something').invoke }.should run_task('foo:test')
  end

  it 'should reset tasks to specific pattern' do
    task('integration:something').invoke
    ['foo', 'foo:bar'].map { |name| project(name) }.each do |project|
      project.test.include?('something').should be_true
      project.test.include?('nothing').should be_false
      project.test.include?('SomeTest').should be_false
    end
  end

  it 'should apply *name* pattern' do
    task('integration:something').invoke
    project('foo').test.include?('prefix-something-suffix').should be_true
    project('foo').test.include?('prefix-nothing-suffix').should be_false
  end

  it 'should not apply *name* pattern if asterisks used' do
    task('integration:*something').invoke
    project('foo').test.include?('prefix-something').should be_true
    project('foo').test.include?('prefix-something-suffix').should be_false
  end

  it 'should accept multiple tasks separated by commas' do
    task('integration:foo,bar').invoke
    project('foo').test.include?('foo').should be_true
    project('foo').test.include?('bar').should be_true
    project('foo').test.include?('baz').should be_false
  end

  it 'should execute only the named tasts' do
    write 'src/test/java/TestSomething.java',
      'public class TestSomething extends junit.framework.TestCase { public void testNothing() {} }'
    write 'src/test/java/TestFails.java', 'class TestFails {}'
    task('integration:Something').invoke
  end
end
