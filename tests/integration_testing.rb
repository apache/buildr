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

BUILDR = ENV['BUILDR'] || File.join(File.expand_path(File.dirname(__FILE__)), "..", "_buildr")

require 'test/unit'

def test(folder, cmd)
  eval <<-TEST
class #{folder.sub("-", "").capitalize} < Test::Unit::TestCase

  def test_#{folder.sub("-", "")}
    result = %x[cd #{File.join(File.expand_path(File.dirname(__FILE__)), "#{folder}")} ; #{cmd} ; #{BUILDR} clean]
    assert($?.success?)
  end

end  
TEST
  
end

class Buildr320 < Test::Unit::TestCase
   
   def test_circular_dependency
     result = %x[cd #{File.join(File.expand_path(File.dirname(__FILE__)), "BUILDR-320")} ; #{BUILDR} --trace -P]
     assert($?.success?)
   end   
end

test("JavaSystemProperty", "#{BUILDR} test")
test("helloWorld", "#{BUILDR} package")
test("compile_with_parent", "#{BUILDR} compile")
test("junit3", "#{BUILDR} test")

class Package_war_as_jar < Test::Unit::TestCase
  
  def test_war_extension_is_jar
    result = %x[cd #{File.join(File.expand_path(File.dirname(__FILE__)), "package_war_as_jar")} ; #{BUILDR} package]
    assert($?.success?)
    assert(File.exist? File.join(File.expand_path(File.dirname(__FILE__)), "package_war_as_jar", "target", "webapp-1.0.jar")) 
    %x[cd #{File.join(File.expand_path(File.dirname(__FILE__)), "package_war_as_jar")} ; #{BUILDR} clean]
    assert($?.success?)
  end
end