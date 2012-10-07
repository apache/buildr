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

def workspace_dir
  "#{File.expand_path(File.join(File.dirname(__FILE__), ".."))}"
end

desc 'Create JRuby all-in-one distribution'
task 'all-in-one' => 'all-in-one:all-in-one'

namespace 'all-in-one' do

  version = '1.6.7'
  jruby_distro = "jruby-bin-#{version}.tar.gz"
  url = "http://jruby.org.s3.amazonaws.com/downloads/#{version}/#{jruby_distro}"
  dir = "jruby-#{version}"

  task 'all-in-one' => %w(gem prepare download_and_extract clean_dist install_dependencies add_execs package)

  desc 'Prepare to run'
  task 'prepare' do
    mkpath '_all-in-one'
    cd '_all-in-one'
  end

  desc 'Download and extract JRuby'
  task 'download_and_extract' do
    unless File.exist?(jruby_distro)
      puts "Downloading JRuby from #{url} ..."
      require 'open-uri'
      File.open(jruby_distro, "wb") do |saved_file|
        # the following "open" is provided by open-uri
        open(url) do |read_file|
          saved_file.write(read_file.read)
        end
      end
      puts '[X] Downloaded JRuby'
    end

    rm_rf dir if File.exist? dir

    puts "Extracting JRuby to #{dir} ..."
    sh 'tar', 'xzf', jruby_distro
    puts '[X] Extracted JRuby'
    cd dir
  end

  desc 'Cleanup JRuby distribution'
  task 'clean_dist' do
    puts 'Cleaning...'
    rm_rf 'docs'
    mkpath 'jruby-docs'
    mv Dir['COPYING*'], 'jruby-docs'
    mv Dir['LICENSE*'], 'jruby-docs'
    mv 'README', 'jruby-docs'
    rm_rf 'lib/ruby/1.9'
    rm_rf 'lib/ruby/gems/1.8/doc'
    rm_rf 'samples'
    rm_rf 'share'
  end

  desc 'Install Buildr gem and dependencies'
  task 'install_dependencies' do
    puts 'Install ffi-ncurses'
    sh 'bin/jruby -S gem install -b ffi-ncurses --version 0.4.0'

    puts 'Install rubygems-update'
    sh 'bin/jruby -S gem install -b rubygems-update'

    puts 'Upgrade Rubygems'
    sh 'bin/jruby -S gem update --system'

    puts 'Install Buildr gem ...'
    sh 'bin/jruby', '-S', 'gem', 'install', FileList['../../pkg/*-java.gem'].first,
       '--no-rdoc', '--no-ri'
    puts '[X] Install Buildr gem'
  end

  desc 'Add Buildr executables/scripts'
  task 'add_execs' do
    cp 'bin/jruby.exe', 'bin/_buildr.exe'
    cp "#{workspace_dir}/all-in-one/buildr", 'bin/buildr'
    cp "#{workspace_dir}/all-in-one/_buildr", 'bin/_buildr'
    cp "#{workspace_dir}/all-in-one/buildr.cmd", 'bin/buildr.cmd'
    File.chmod(0500, 'bin/_buildr', 'bin/buildr')
  end

  desc 'Package distribution'
  task 'package' do
    pkg_dir = "#{workspace_dir}/pkg"
    mkpath pkg_dir
    puts 'Zipping distribution ...'
    cd '..'
    new_dir  = "#{spec.name}-all-in-one-#{spec.version}"
    mv dir, new_dir
    zip = "#{pkg_dir}/#{new_dir}.zip"
    rm zip if File.exist? zip
    sh 'zip', '-q', '-r', zip, new_dir
    puts '[X] Zipped distribution'

    puts 'Tarring distribution ...'
    tar = "#{pkg_dir}/#{new_dir}.tar.gz"
    rm tar if File.exist? tar
    sh 'tar', 'czf', tar, new_dir
    puts '[X] Tarred distribution'

    rm_rf new_dir
  end

end

task('clobber') { rm_rf '_all-in-one' }
