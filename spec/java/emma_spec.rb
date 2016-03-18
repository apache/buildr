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

require File.expand_path(File.join(File.dirname(__FILE__), 'test_coverage_helper'))
if ENV_JAVA['java.version'] < "1.7"

Sandbox.require_optional_extension 'buildr/java/emma'
artifacts(Buildr::Emma::dependencies).map(&:invoke)


describe Buildr::Emma do
  include TestCoverageHelper

  before do
    # Reloading the extension because the sandbox removes all its actions
    Buildr.module_eval { remove_const :Emma }
    load File.expand_path('../lib/buildr/java/emma.rb')
    @tool_module = Buildr::Emma
  end

  it_should_behave_like 'test coverage tool'

  describe 'project-specific' do
    describe 'metadata file' do
      it 'should have a default value' do
        expect(define('foo').emma.metadata_file).to point_to_path('reports/emma/coverage.em')
      end

      it 'should be overridable' do
        define('foo') { emma.metadata_file = path_to('target/metadata.emma') }
        expect(project('foo').emma.metadata_file).to point_to_path('target/metadata.emma')
      end

      it 'should be created during instrumentation' do
        write 'src/main/java/Foo.java', 'public class Foo {}'
        define('foo')
        task('foo:emma:instrument').invoke
        expect(file(project('foo').emma.metadata_file)).to exist
      end
    end

    describe 'coverage file' do
      it 'should have a default value' do
        expect(define('foo').emma.coverage_file).to point_to_path('reports/emma/coverage.ec')
      end

      it 'should be overridable' do
        define('foo') { emma.coverage_file = path_to('target/coverage.emma') }
        expect(project('foo').emma.coverage_file).to point_to_path('target/coverage.emma')
      end

      it 'should be created during test' do
        write 'src/main/java/Foo.java', 'public class Foo {}'
        write_test :for=>'Foo', :in=>'src/test/java'
        define('foo')
        task('foo:test').invoke
        expect(file(project('foo').emma.coverage_file)).to exist
      end
    end

    describe 'instrumentation' do
      before do
        ['Foo', 'Bar'].each { |cls| write File.join('src/main/java', "#{cls}.java"), "public class #{cls} {}" }
      end

      it 'should instrument only included classes' do
        define('foo') { emma.include 'Foo' }
        task("foo:emma:instrument").invoke
        Dir.chdir('target/instrumented/classes') { expect(Dir.glob('*').sort).to eq(['Foo.class']) }
      end

      it 'should not instrument excluded classes' do
        define('foo') { emma.exclude 'Foo' }
        task("foo:emma:instrument").invoke
        Dir.chdir('target/instrumented/classes') { expect(Dir.glob('*').sort).to eq(['Bar.class']) }
      end

      it 'should instrument classes that are included but not excluded' do
        write 'src/main/java/Baz.java', 'public class Baz {}'
        define('foo') { emma.include('Ba*').exclude('*ar') }
        task("foo:emma:instrument").invoke
        Dir.chdir('target/instrumented/classes') { expect(Dir.glob('*').sort).to eq(['Baz.class']) }
      end
    end

    describe 'reports' do
      before do
        write 'src/main/java/Foo.java', 'public class Foo {}'
        write_test :for=>'Foo', :in=>'src/test/java'
      end

      describe 'in html' do
        it 'should inform the user if no coverage data' do
          rm 'src/test/java/FooTest.java'
          define('foo')
          expect { task('foo:emma:html').invoke }.
            to show_info(/No test coverage report for foo. Missing: #{project('foo').emma.coverage_file}/)
        end
      end

      describe 'in xml' do
        it 'should have an xml file' do
          define('foo')
          task('foo:emma:xml').invoke
          expect(file(File.join(project('foo').emma.report_dir, 'coverage.xml'))).to exist
        end
      end
    end
  end
end

end
