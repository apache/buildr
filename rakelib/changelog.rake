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


# Handling of CHANGELOG.
namespace 'changelog' do

  task 'check'=>'CHANGELOG' do
    print 'Checking that CHANGELOG indicates most recent version and today\'s date ... '
    expecting = "#{spec.version} (#{Time.now.strftime('%Y-%m-%d')})"
    header = File.readlines('CHANGELOG').first.chomp
    fail "Expecting CHANGELOG to start with #{expecting}, but found #{header} instead" unless expecting == header
    puts 'OK'
  end

  task 'prepare'=>'CHANGELOG' do
    # Read the changes for this release.
    print 'Looking for changes between this release and previous one ... '
    pattern = /(^(\d+\.\d+(?:\.\d+)?)\s+\(\d{4}-\d{2}-\d{2}\)\s*((:?^[^\n]+\n)*))/
    changes = File.read('CHANGELOG').scan(pattern).inject({}) { |hash, set| hash[set[1]] = set[2] ; hash }
    current = changes[spec.version.to_s]
    fail "No changeset found for version #{spec.version}" unless current
    File.open 'stage/CHANGES', 'w' do |file|
      file.write current
    end
    puts 'OK'
  end

  task 'wrapup'=>'CHANGELOG' do
    next_version = spec.version.to_ints.zip([0, 0, 1]).map { |a| a.inject(0) { |t,i| t + i } }.join('.')
    print 'Adding new entry to CHANGELOG ... '
    modified = "#{next_version} (Pending)\n\n" + File.read('CHANGELOG')
    File.open 'CHANGELOG', 'w' do |file|
      file.write modified
    end
    puts 'Done'
  end

end

task 'stage:check'=>'changelog:check'
task 'stage:prepare'=>'changelog:prepare'
task 'release:wrapup'=>'changelog:wrapup'
