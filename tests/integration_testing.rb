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
require 'zip/zip'

module Buildr
  module IntegrationTests

    def self.test(folder, cmd, after_block = nil)

      eval <<-TEST
      class #{folder.sub("-", "").capitalize} < Test::Unit::TestCase

        def test_#{folder.sub("-", "")}
          begin
            result = `cd #{TEST_DIR}/#{folder} ; #{BUILDR} #{cmd}`
            assert($?.success?, 'Command success?')
            #{ after_block || "" }
          ensure
            %x[cd #{TEST_DIR}/#{folder} ; #{BUILDR} clean]
          end

        end

      end
      TEST

    end

    #BUILDR-320 still not resolved.
    #test "BUILDR-320", "--trace -P"

    test "JavaSystemProperty", "test"

    test "helloWorld", "package"

    test "compile_with_parent", "compile"

    test "junit3", "test"

    test "include_path", "package", <<-CHECK
path = File.expand_path("#{TEST_DIR}/include_path/target/proj-1.0.zip")
assert(File.exist?(path), "File exists?")
Zip::ZipFile.open(path) {|zip|
assert(!zip.get_entry("distrib/doc/index.html").nil?)
assert(!zip.get_entry("distrib/lib/slf4j-api-1.6.1.jar").nil?)
}
    CHECK

    test "include_as", "package", <<-CHECK
path = File.expand_path("#{TEST_DIR}/include_as/target/proj-1.0.zip")
assert(File.exist? path)
Zip::ZipFile.open(path) {|zip|
assert(!zip.get_entry("docu/index.html").nil?)
assert(!zip.get_entry("lib/logging.jar").nil?)
}
    CHECK

    test "package_war_as_jar", "package", <<-CHECK
    assert(File.exist? "#{TEST_DIR}/package_war_as_jar/target/webapp-1.0.jar")
    %x[cd #{TEST_DIR}/package_war_as_jar ; #{BUILDR} clean]
    assert($?.success?)
    CHECK

  end
end
