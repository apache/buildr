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


# Staged files are copied to this directory first, and from there uploaded to the staging server.
directory 'staged'

task 'clobber' do
  rm_rf 'staged'
end

namespace 'stage' do
  # stage:check verifies that we're able to stage a release: check for a changelog,
  # local changes, run all the test cases, etc.  You can add more actions, e.g.
  # checking license files, spell checking documentation.
  task 'check'=>['setup', 'clobber']

  # stage:prepare prepares all the files necessary for making a successful release:
  # binary and source packages, documentation, Web site, change file, checksums, etc.
  # This task depends on stage:check, and also performs its own verification of the
  # produced artifacts.  Staged files are placed in the staged directory.
  task 'prepare'=>'staged'

  # stage:upload moves the stage directory to the staging server.
  task 'upload' do |task, args|
    puts "Uploading staged directory to #{args.staging} ..."
    sh 'rsync', '--progress', '--recursive', 'staged/', args.staging
    puts 'Done'
  end
end

desc 'Stage files for the release, upload them to staging server'
task 'stage'=>['stage:check', 'stage:prepare', 'stage:upload']
