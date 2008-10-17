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


begin
  require 'rubyforge'
rescue LoadError
  puts 'Please run rake setup to install the RubyForge gem'
  task 'setup' do
    install_gem 'rubyforge'
  end
  task 'release:check' do
    fail 'Please run rake setup to install the RubyForge gem'
  end
end


namespace 'rubyforge' do

  file 'published/rubyforge'=>'published' do
    mkdir 'published/rubyforge'
    FileList['published/distro/*.{gem,tgz,zip}'].each do |pkg|
      cp pkg, 'published/rubyforge/' + File.basename(pkg).sub(/-incubating/, '')
    end
  end

  task 'release'=>'published/rubyforge' do |task|
    changes = FileList['published/CHANGES'].first
    files = FileList['published/rubyforge/*.{gem,tgz,zip}'].exclude(changes).existing
    print "Uploading #{spec.version} to RubyForge ... "
    rubyforge = RubyForge.new
    rubyforge.configure
    rubyforge.login 
    rubyforge.userconfig.merge!('release_changes'=>changes,  'preformatted' => true) if changes
    rubyforge.add_release spec.rubyforge_project.downcase, spec.name.downcase, spec.version.to_s, *files
    puts 'Done'
  end

end

task 'release:publish'=>'rubyforge:release'
