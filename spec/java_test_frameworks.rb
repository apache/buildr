require File.join(File.dirname(__FILE__), 'spec_helpers')


describe Buildr::JUnit do
  before do
    write "src/test/java/PassingTest.java", 
      "public class PassingTest extends junit.framework.TestCase { public void testNothing() {} }"
    write "src/test/java/FailingTest.java", 
      "public class FailingTest extends junit.framework.TestCase { public void testNothing() { assertTrue(false); } }"
    define "foo"
  end

  it "should include JUnit requirements" do
    project("foo").test.requires.should include(*JUnit::REQUIRES)
    project("foo").test.compile.dependencies.should include(*artifacts(JUnit::REQUIRES))
    project("foo").test.dependencies.should include(*artifacts(JUnit::REQUIRES))
  end

  it "should include JMock requirements" do
    project("foo").test.requires.should include(*JMock::REQUIRES)
    project("foo").test.compile.dependencies.should include(*artifacts(JMock::REQUIRES))
    project("foo").test.dependencies.should include(*artifacts(JMock::REQUIRES))
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


describe Rake::Task, "junit:report" do

  it "should default to the target directory reports/junit" do
    JUnit.report.target.should eql("reports/junit")
  end

  it "should generate report into the target directory" do
    JUnit.report.target = "test-report"
    lambda { task("junit:report").invoke }.should change { File.exist?(JUnit.report.target) }.to(true)
  end

  it "should clean after itself" do
    mkpath JUnit.report.target
    lambda { task("clean").invoke }.should change { File.exist?(JUnit.report.target) }.to(false)
  end

  it "should generate a consolidated XML report" do
    lambda { task("junit:report").invoke }.should change { File.exist?("reports/junit/TESTS-TestSuites.xml") }.to(true)
  end

  it "should default to generating a report with frames" do
    JUnit.report.frames.should be_true
  end

  it "should generate single page when frames is false" do
    JUnit.report.frames = false
    task("junit:report").invoke
    file("reports/junit/html/junit-noframes.html").should exist
  end

  it "should generate frame page when frames is false" do
    JUnit.report.frames = true
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
    JUnit.instance_eval { @report = nil }
  end
end


describe Buildr::TestNG do
  before do
    write "src/test/java/PassingTest.java", 
      "public class PassingTest { @org.testng.annotations.Test public void testNothing() {} }"
    write "src/test/java/FailingTest.java", 
      "public class FailingTest { @org.testng.annotations.Test public void testNothing() { org.testng.AssertJUnit.assertTrue(false); } }"
    define("foo") { test.using :testng }
  end

  it "should include TestNG requirements" do
    project("foo").test.requires.should include(*TestNG::REQUIRES)
    project("foo").test.compile.dependencies.should include(*artifacts(TestNG::REQUIRES))
    project("foo").test.dependencies.should include(*artifacts(TestNG::REQUIRES))
  end

  it "should include TestNG requirements" do
    project("foo").test.requires.should include(*JMock::REQUIRES)
    project("foo").test.compile.dependencies.should include(*artifacts(JMock::REQUIRES))
    project("foo").test.dependencies.should include(*artifacts(JMock::REQUIRES))
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


