require File.join(File.dirname(__FILE__), 'spec_helpers')


describe Buildr::JUnit do
  it 'should be the default test framework when test cases are in java'

  it 'should be picked if the test language is Java' do
    define 'foo' do
      test.compile.using(:javac)
      test.framework.should eql(:junit)
    end
  end

  it 'should include JUnit dependencies' do
    define('foo') { test.using(:junit) }
    project('foo').test.compile.dependencies.should include(*artifacts(JUnit::REQUIRES))
    project('foo').test.dependencies.should include(*artifacts(JUnit::REQUIRES))
  end

  it 'should include JMock dependencies' do
    define('foo') { test.using(:junit) }
    project('foo').test.compile.dependencies.should include(*artifacts(JMock::REQUIRES))
    project('foo').test.dependencies.should include(*artifacts(JMock::REQUIRES))
  end

  it 'should include public classes extending junit.framework.TestCase' do
    write 'src/test/java/FirstTest.java', <<-JAVA
      public class FirstTest extends junit.framework.TestCase { }
    JAVA
    write 'src/test/java/AnotherOne.java', <<-JAVA
      public class AnotherOne extends junit.framework.TestCase { }
    JAVA
    define('foo').test.compile.invoke
    project('foo').test.tests.should include('FirstTest', 'AnotherOne')
  end

  it 'should ignore classes not extending junit.framework.TestCase' do
    write 'src/test/java/NotATest.java', <<-JAVA
      public class NotATest { }
    JAVA
    define('foo').test.compile.invoke
    project('foo').test.tests.should be_empty
  end

  it 'should ignore inner classes' do
    write 'src/test/java/InnerClassTest.java', <<-JAVA
      public class InnerClassTest extends junit.framework.TestCase {
        public class InnerTest extends junit.framework.TestCase {
        }
      }
    JAVA
    define('foo').test.compile.invoke
    project('foo').test.tests.should eql(['InnerClassTest'])
  end

  it 'should pass when JUnit test case passes' do
    write 'src/test/java/PassingTest.java', <<-JAVA
      public class PassingTest extends junit.framework.TestCase { public void testNothing() {}  }
    JAVA
    lambda { define('foo').test.invoke }.should_not raise_error
  end

  it 'should fail when JUnit test case fails' do
    write 'src/test/java/FailingTest.java', <<-JAVA
      public class FailingTest extends junit.framework.TestCase { public void testFailure() { assertTrue(false); } }
    JAVA
    lambda { define('foo').test.invoke }.should raise_error(RuntimeError, /Tests failed/) rescue nil
  end

  it 'should report failed test names' do
    write 'src/test/java/FailingTest.java', <<-JAVA
      public class FailingTest extends junit.framework.TestCase { public void testFailure() { assertTrue(false); } }
    JAVA
    define('foo').test.invoke rescue
    project('foo').test.failed_tests.should include('FailingTest')
  end

  it 'should report to reports/junit' do
    write 'src/test/java/PassingTest.java', <<-JAVA
      public class PassingTest extends junit.framework.TestCase { public void testNothing() {} }
    JAVA
    define 'foo' do
      test.report_to.should be(file('reports/junit'))
    end
    project('foo').test.invoke
    project('foo').file('reports/junit/TEST-PassingTest.txt').should exist
    project('foo').file('reports/junit/TEST-PassingTest.xml').should exist
  end

  it 'should pass properties to JVM' do
    write 'src/test/java/PropertyTest.java', <<-JAVA
      public class PropertyTest extends junit.framework.TestCase {
        public void testProperty() {
          assertEquals("value", System.getProperty("name"));
        }
      }
    JAVA
    define('foo').test.using :properties=>{ 'name'=>'value' }
    project('foo').test.invoke
  end

  it 'should set current directory' do
    mkpath 'baz'
    write 'baz/src/test/java/CurrentDirectoryTest.java', <<-JAVA
      public class CurrentDirectoryTest extends junit.framework.TestCase {
        public void testCurrentDirectory() throws Exception {
          assertEquals("#{File.expand_path('baz')}", new java.io.File(".").getCanonicalPath());
        }
      }
    JAVA
    define 'bar' do
      define 'baz' do
        test.include 'CurrentDirectoryTest'
      end
    end
    project('bar:baz').test.invoke
  end

  def fork_tests(mode)
    write 'src/test/java/Shared.java', <<-JAVA
      public class Shared {
        public static boolean flag = false;
      }
    JAVA
    write 'src/test/java/TestCase1.java', <<-JAVA
      public class TestCase1 extends junit.framework.TestCase {
        public void testSameVM() { assertFalse(Shared.flag); Shared.flag = true; }
      }
    JAVA
    write 'src/test/java/TestCase2.java', <<-JAVA
      public class TestCase2 extends junit.framework.TestCase {
        public void testSameVM() { assertFalse(Shared.flag); Shared.flag = true; }
      }
    JAVA
    define 'foo' do
      test.using :fork=>mode, :fail_on_failure=>false
    end
    project('foo').test.invoke
  end

  it 'should run all test cases in same VM if fork is once' do
    fork_tests :once
    project('foo').test.failed_tests.size.should eql(1)
  end

  it 'should run each test case in separate same VM if fork is each' do
    fork_tests :each
    project('foo').test.failed_tests.should be_empty
  end
end


describe Buildr::JUnit, 'report' do

  it 'should default to the target directory reports/junit' do
    JUnit.report.target.should eql('reports/junit')
  end

  it 'should generate report into the target directory' do
    JUnit.report.target = 'test-report'
    lambda { task('junit:report').invoke }.should change { File.exist?(JUnit.report.target) }.to(true)
  end

  it 'should clean after itself' do
    mkpath JUnit.report.target
    lambda { task('clean').invoke }.should change { File.exist?(JUnit.report.target) }.to(false)
  end

  it 'should generate a consolidated XML report' do
    lambda { task('junit:report').invoke }.should change { File.exist?('reports/junit/TESTS-TestSuites.xml') }.to(true)
  end

  it 'should default to generating a report with frames' do
    JUnit.report.frames.should be_true
  end

  it 'should generate single page when frames is false' do
    JUnit.report.frames = false
    task('junit:report').invoke
    file('reports/junit/html/junit-noframes.html').should exist
  end

  it 'should generate frame page when frames is false' do
    JUnit.report.frames = true
    task('junit:report').invoke
    file('reports/junit/html/index.html').should exist
  end

  it 'should generate reports from all projects that ran test cases' do
    write 'src/test/java/TestSomething.java',
      'public class TestSomething extends junit.framework.TestCase { public void testNothing() {} }'
    define 'foo'
    project('foo').test.invoke
    task('junit:report').invoke
    FileList['reports/junit/html/*TestSomething.html'].size.should be(1)
  end

  after do
    JUnit.instance_eval { @report = nil }
  end
end


describe Buildr::TestNG do
  before do
    write 'src/test/java/PassingTest.java', 
      'public class PassingTest { @org.testng.annotations.Test public void testNothing() {} }'
    write 'src/test/java/FailingTest.java', 
      'public class FailingTest { @org.testng.annotations.Test public void testNothing() { org.testng.AssertJUnit.assertTrue(false); } }'
    define('foo') { test.using :testng }
  end


  it 'should be selectable in parent project'

  it 'should include TestNG dependencies' do
    project('foo').test.compile.dependencies.should include(*artifacts(TestNG::REQUIRES))
    project('foo').test.dependencies.should include(*artifacts(TestNG::REQUIRES))
  end

  it 'should include TestNG dependencies' do
    project('foo').test.compile.dependencies.should include(*artifacts(JMock::REQUIRES))
    project('foo').test.dependencies.should include(*artifacts(JMock::REQUIRES))
  end

  it 'should include classes starting with and ending with Test' do
    ['TestThis', 'ThisTest', 'ThisThat'].each do |name|
      write File.join(project('foo').test.compile.target.to_s, name).ext('class')
    end
    project('foo').test.tests.map { |file| File.basename(file) }.should == ['TestThis', 'ThisTest']
  end

  it 'should ignore inner classes' do
    ['TestThis', 'TestThis$Innner'].each do |name|
      write "target/test/classes/#{name}.class"
    end
    project('foo').test.tests.map { |file| File.basename(file) }.should == ['TestThis']
  end

  it 'should pass when TestNG test case passes' do
    project('foo').test.include 'PassingTest'
    lambda { project('foo').test.invoke }.should_not raise_error
  end

  it 'should fail when TestNG test case fails' do
    project('foo').test.include 'FailingTest'
    lambda { project('foo').test.invoke }.should raise_error(RuntimeError, /Tests failed/)
  end

  it 'should report failed test names' do
    project('foo').test.include 'FailingTest'
    project('foo').test.invoke rescue
    project('foo').test.failed_tests.should eql(['FailingTest'])
  end

  it 'should report to reports/testng' do
    project('foo').test.report_to.should be(project('foo').file('reports/testng'))
  end

  it 'should generate reports' do
    project('foo').test.include 'PassingTest'
    lambda { project('foo').test.invoke }.should change { File.exist?(project('foo').test.report_to.to_s) }.to(true)
  end
end


