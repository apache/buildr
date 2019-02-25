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

TEST_DIR = File.dirname(File.expand_path(__FILE__))
BUILDR = ENV['BUILDR'] || File.expand_path("#{TEST_DIR}/../_buildr")

require 'test/unit'
require 'zip'
require 'open-uri'

module Buildr
  module IntegrationTests

    def self.test(folder, cmd, after_block = nil, cleanup = "#{BUILDR} clean")

      eval <<-TEST
      class #{folder.sub("-", "").capitalize} < Test::Unit::TestCase

        def test_#{folder.sub("-", "")}
          begin
            result = `cd #{TEST_DIR}/#{folder} ; #{BUILDR} #{cmd}`
            assert($?.success?, 'Command success?')
            #{ after_block || "" }
          ensure
            %x[cd #{TEST_DIR}/#{folder} ; #{cleanup}]
          end

        end

      end
      TEST

    end

    test "BUILDR-320", "package --trace -P"

    test "JavaSystemProperty", "test"

    test "helloWorld", "package"

    test "helloWorldEcj", "package", %Q(
p result
#assert(::Buildr::Java.classpath.include?(artifact("org.eclipse.jdt.core.compiler:ecj:jar:3.5.1").to_s))
    )

    test "compile_with_parent", "compile"

    test "junit3", "test"

    test "include_path", "package", %Q(
path = File.expand_path("#{TEST_DIR}/include_path/target/proj-1.0.zip")
assert(File.exist?(path), "File exists?")
::Zip::File.open(path) {|zip|
assert(!zip.get_entry("distrib/doc/index.html").nil?)
assert(!zip.get_entry("distrib/lib/slf4j-api-1.6.1.jar").nil?)
}
    )

    test "include_as", "package", %Q(
path = File.expand_path("#{TEST_DIR}/include_as/target/proj-1.0.zip")
assert(File.exist? path)
::Zip::File.open(path) {|zip|
assert(!zip.get_entry("docu/index.html").nil?)
assert(!zip.get_entry("lib/logging.jar").nil?)
}
    )

    test "package_war_as_jar", "package", %Q(
    assert(File.exist? "#{TEST_DIR}/package_war_as_jar/target/webapp-1.0.jar")
    %x[cd #{TEST_DIR}/package_war_as_jar ; #{BUILDR} clean]
    assert($?.success?)
    )

    test "generateFromPom", "--generate pom.xml", %Q(
    assert(File.exist? "#{TEST_DIR}/generateFromPom/buildfile")
    assert(File.read("#{TEST_DIR}/generateFromPom/buildfile") !~ /slf4j.version/)
    ), 'rm Buildfile'

    test "generateFromPom2", "--generate pom.xml", '', 'rm Buildfile' # For BUILDR-623

    class RunJetty6 < Test::Unit::TestCase

      def test_RunJetty6
        begin
          result = `cd #{TEST_DIR}/run_jetty6 ; #{BUILDR} clean package`
          assert($?.success?, 'Command success?')
          system "cd #{TEST_DIR}/run_jetty6 ; #{BUILDR} jetty:start &"
          sleep 5
          system "cd #{TEST_DIR}/run_jetty6 ; #{BUILDR} webapp:deploy-app"
          sleep 5
          http_resp = open('http://localhost:8080/hello/').read
          assert("Hello!\n" == http_resp)
        ensure
          %x[cd #{TEST_DIR}/run_jetty6 ; #{BUILDR} jetty:stop clean]
          system "ps aux | grep jetty:start | awk '{print $2}' | xargs kill -9"
        end

      end
    end

    class RunJetty9 < Test::Unit::TestCase

      def test_RunJetty9
        begin
          result = `cd #{TEST_DIR}/run_jetty9 ; #{BUILDR} clean package`
          assert($?.success?, 'Command success?')
          system "cd #{TEST_DIR}/run_jetty9 ; #{BUILDR} jetty:start &"
          sleep 5
          system "cd #{TEST_DIR}/run_jetty9 ; #{BUILDR} webapp:deploy-app"
          sleep 5
          http_resp = open('http://localhost:8080/hello/').read
          assert("Hello!\n" == http_resp)
        ensure
          %x[cd #{TEST_DIR}/run_jetty9 ; #{BUILDR} jetty:stop clean]
          system "ps aux | grep jetty:start | awk '{print $2}' | xargs kill -9"
        end

      end
    end
  end

end
