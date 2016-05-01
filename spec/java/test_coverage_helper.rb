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


module TestCoverageHelper
  def write_test options
    write File.join(options[:in], "#{options[:for]}Test.java"),
      "public class #{options[:for]}Test extends junit.framework.TestCase { public void test#{options[:for]}() { new #{options[:for]}(); } }"
  end

  # Rspec matcher using file glob patterns.
  class FileNamePatternMatcher
    def initialize(pattern)
      @expected_pattern = pattern
      @pattern_matcher = lambda { |filename| File.fnmatch? pattern, filename }
    end

    def matches?(directory)
      @actual_filenames = Dir[File.join(directory,'*')]
      @actual_filenames.any? &@pattern_matcher
    end

    def failure_message
      "Expected to find at least one element matching '#{@expected_pattern}' among #{@actual_filenames.inspect}, but found none"
    end

    def failure_message_when_negated
      "Expected to find no element matching '#{@expected_pattern}' among #{@actual_filenames.inspect}, but found matching element(s) #{@actual_filenames.select(&@pattern_matcher).inspect}"
    end
  end

  # Test if a directory contains at least one file matching a given glob pattern.
  #
  # For example, to check that a directory contains at least one HTML file:
  #   '/path/to/some/directory'.should have_files_matching('*.html')
  def have_files_matching pattern
    FileNamePatternMatcher.new pattern
  end
end

shared_examples_for 'test coverage tool' do
  include TestCoverageHelper

  def toolname
    @tool_module.name.split('::').last.downcase
  end

  def test_coverage_config
    project('foo').send(toolname)
  end

  describe 'project-specific' do

    before do
      write 'src/main/java/Foo.java', 'public class Foo {}'
      write_test :for=>'Foo', :in=>'src/test/java'
    end

    describe 'clean' do
      before { define('foo') }

      it 'should remove the instrumented directory' do
        mkdir_p test_coverage_config.instrumented_dir.to_s
        task('foo:clean').invoke
        expect(file(test_coverage_config.instrumented_dir)).not_to exist
      end

      it 'should remove the reporting directory' do
        mkdir_p test_coverage_config.report_dir
        task('foo:clean').invoke
        expect(file(test_coverage_config.report_dir)).not_to exist
      end
    end

    describe 'instrumented directory' do
      it 'should have a default value' do
        define('foo')
        expect(test_coverage_config.instrumented_dir).to point_to_path('target/instrumented/classes')
      end

      it 'should be overridable' do
        toolname = toolname()
        define('foo') { send(toolname).instrumented_dir = path_to('target/coverage/classes') }
        expect(test_coverage_config.instrumented_dir).to point_to_path('target/coverage/classes')
      end

      it 'should be created during instrumentation' do
        define('foo')
        task("foo:#{toolname}:instrument").invoke
        expect(file(test_coverage_config.instrumented_dir)).to exist
      end
    end

    describe 'instrumentation' do
      def instrumented_dir
        file(test_coverage_config.instrumented_dir)
      end

      it 'should happen after compile' do
        define('foo')
        expect { task("foo:#{toolname}:instrument").invoke }.to run_task('foo:compile')
      end

      it 'should put classes from compile.target in the instrumented directory' do
        define('foo')
        task("foo:#{toolname}:instrument").invoke
        expect(Dir.entries(instrumented_dir.to_s)).to eq(Dir.entries(project('foo').compile.target.to_s))
      end

      it 'should touch instrumented directory if anything instrumented' do
        a_long_time_ago = Time.now - 10
        define('foo')
        mkpath instrumented_dir.to_s
        File.utime(a_long_time_ago, a_long_time_ago, instrumented_dir.to_s)
        task("foo:#{toolname}:instrument").invoke
        expect(instrumented_dir.timestamp).to be_within(2).of(Time.now)
      end

      it 'should not touch instrumented directory if nothing instrumented' do
        a_long_time_ago = Time.now - 10
        define('foo').compile.invoke
        mkpath instrumented_dir.to_s
        [project('foo').compile.target, instrumented_dir].map(&:to_s).each { |dir| File.utime(a_long_time_ago, a_long_time_ago, dir) }
        task("foo:#{toolname}:instrument").invoke
        expect(instrumented_dir.timestamp).to be_within(2).of(a_long_time_ago)
      end
    end

    describe 'testing classpath' do
      it 'should give priority to instrumented classes over non-instrumented ones' do
        define('foo')
        depends = project('foo').test.dependencies
        expect(depends.index(test_coverage_config.instrumented_dir)).to be < depends.index(project('foo').compile.target)
      end

      it 'should have the test coverage tools artifacts' do
        define('foo')
        artifacts(@tool_module.dependencies).each { |artifact| expect(project('foo').test.dependencies).to include(artifact) }
      end
    end

    describe 'html report' do
      it 'should have html files' do
        define('foo')
        task("foo:#{toolname}:html").invoke
        expect(test_coverage_config.report_to(:html)).to have_files_matching('*.html')
      end

      it 'should contain full source code, including comments' do
        write 'src/main/java/Foo.java',
          'public class Foo { /* This comment is a TOKEN to check that test coverage reports include the source code */ }'
        define('foo')
        task("foo:#{toolname}:html").invoke
        html_report_contents = Dir[File.join(test_coverage_config.report_dir, '**/*.html')].map{|path|File.open(path).read}.join
        html_report_contents.force_encoding('ascii-8bit') if RUBY_VERSION >= '1.9'
        expect(html_report_contents).to match(/TOKEN/)
      end
    end
  end

  describe 'cross-project' do
    describe 'reporting' do
      before do
        write 'src/main/java/Foo.java', 'public class Foo {}'
        write 'bar/src/main/java/Bar.java', 'public class Bar {}'
        write_test :for=>'Bar', :in=>'bar/src/test/java'
        define('foo') { define('bar') }
      end

      it 'should have a default target' do
        expect(@tool_module.report_to).to point_to_path(File.join('reports', toolname))
      end

      describe 'in html' do
        it 'should be a defined task' do
          expect(Rake::Task.task_defined?("#{toolname}:html")).to be(true)
        end

        it 'should happen after project instrumentation and testing' do
          expect { task("#{toolname}:html").invoke }.to run_tasks(["foo:#{toolname}:instrument", 'foo:bar:test'])
        end

        it 'should have html files' do
          task("#{toolname}:html").invoke
          expect(@tool_module.report_to(:html)).to have_files_matching('*.html')
        end

        it 'should contain full source code, including comments' do
          write 'bar/src/main/java/Bar.java',
            'public class Bar { /* This comment is a TOKEN to check that test coverage reports include the source code */ }'
          task("#{toolname}:html").invoke
          html_report_contents = Dir[File.join(@tool_module.report_to(:html), '**/*.html')].map{|path|File.read(path)}.join
          html_report_contents.force_encoding('ascii-8bit') if RUBY_VERSION >= '1.9'
          expect(html_report_contents).to match(/TOKEN/)
        end

        it 'should handle gracefully a project with no source' do
          define 'baz', :base_dir=>'baz'
          task("#{toolname}:html").invoke
          expect { task("#{toolname}:html").invoke }.not_to raise_error
        end
      end
    end

    describe 'clean' do
      it 'should remove the report directory' do
        define('foo')
        mkdir_p @tool_module.report_to
        task("#{toolname}:clean").invoke
        expect(file(@tool_module.report_to)).not_to exist
      end

      it 'should be called when calling global clean' do
        define('foo')
        expect { task('clean').invoke }.to run_task("#{toolname}:clean")
      end
    end
  end

  describe 'project with no source' do
    it 'should not define an html report task' do
      define 'foo'
      expect(Rake::Task.task_defined?("foo:#{toolname}:html")).to be(false)
    end

    it 'should not raise an error when instrumenting' do
      define('foo')
      expect { task("foo:#{toolname}:instrument").invoke }.not_to raise_error
    end

    it 'should not add the instrumented directory to the testing classpath' do
      define 'foo'
      depends = project('foo').test.dependencies
      expect(depends).not_to include(test_coverage_config.instrumented_dir)
    end

    it 'should not add the test coverage tools artifacts to the testing classpath' do
      define('foo')
      @tool_module.dependencies.each { |artifact| expect(project('foo').test.dependencies).not_to include(artifact) }
    end
  end
end
