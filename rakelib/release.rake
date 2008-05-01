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

# Released files are placed in this directory first, and from there published to various servers.
file 'published' do |task, args|
  mkpath task.name
  puts "Populating published directory from #{args.staging} ..."
  sh 'rsync', '--progress', '--recursive', "#{args.staging}/", 'published'
  puts 'Done'
end

task 'clobber' do
  rm_rf 'published'
end

namespace 'release' do
  task 'prepare'=>['setup', 'clobber', 'published']

  task 'publish'

  task 'wrapup'
end

desc "Make a release using previously staged files"
task 'release'=>['release:prepare', 'release:publish', 'release:wrapup']


task 'next_version' do
  ver_file = "lib/#{spec.name}.rb"
  if File.exist?(ver_file)
    next_version = spec.version.to_s.split('.').map { |v| v.to_i }.
      zip([0, 0, 1]).map { |a| a.inject(0) { |t,i| t + i } }.join('.')
    print "Updating #{ver_file} to next version number (#{next_version}) ... "
    modified = File.read(ver_file).sub(/(VERSION\s*=\s*)(['"])(.*)\2/) { |line| "#{$1}#{$2}#{next_version}#{$2}" } 
    File.open ver_file, 'w' do |file|
      file.write modified
    end
    puts 'Done'
  end
end

task 'release:wrapup'=>'next_version'
