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


require 'digest/md5'
require 'digest/sha1'


# Tasks specific to Apache projects (license, release, etc).
namespace 'apache' do

  desc 'Upload snapshot packages over to people.apache.org'
  task 'snapshot'=>['spec', 'package'] do
    rm_rf 'snapshot' # Always start with empty directory
    puts "Copying existing gems from Apache"
    sh 'rsync', '--progress', '--recursive', 'people.apache.org:public_html/buildr/snapshot', './'
    puts "Copying new gems over"
    cp FileList['pkg/{*.gem,*.tgz,*.zip}'], 'snapshot/gems'
    puts "Generating gem index ..."
    sh 'gem', 'generate_index', '--directory', 'snapshot'
    puts "Copying gem and index back to Apache" 
    sh 'rsync', '--progress', '--recursive', 'snapshot', 'people.apache.org:public_html/buildr/'
  end


  desc 'Check that source files contain the Apache license'
  task 'license' do |task|
    print 'Checking that files contain the Apache license ... '
    required = task.prerequisites.select { |fn| File.file?(fn) }
    missing = required.reject { |fn| 
      comments = File.read(fn).scan(/(\/\*(.*?)\*\/)|^#\s+(.*?)$|^-#\s+(.*?)$|<!--(.*?)-->/m).
        map { |match| match.compact }.flatten.join("\n")
      comments =~ /Licensed to the Apache Software Foundation/ && comments =~ /http:\/\/www.apache.org\/licenses\/LICENSE-2.0/
    }
    fail "#{missing.join(', ')} missing Apache License, please add it before making a release!" unless missing.empty?
    puts 'OK'
  end
  
  # Staging checks specific for Apache.
  task 'check'=>'license'


  file 'staged/distro'=>'package' do
    puts 'Copying and signing release files ...'
    mkpath 'staged/distro'
    FileList['pkg/*.{gem,zip,tgz}'].each do |pkg|
      cp pkg, pkg.pathmap('staged/distro/%n-incubating%x') 
    end
  end

  task 'sign'=>['etc/KEYS', 'staged/distro'] do |task, args|
    gpg_user = args.gpg_user or fail "Please run with gpg_user=<argument for gpg --local-user>"
    puts "Signing packages in staged/distro as user #{gpg_user}"
    FileList['staged/distro/*.{gem,zip,tgz}'].each do |pkg|
      bytes = File.open(pkg, 'rb') { |file| file.read }
      File.open(pkg + '.md5', 'w') { |file| file.write Digest::MD5.hexdigest(bytes) << ' ' << File.basename(pkg) }
      File.open(pkg + '.sha1', 'w') { |file| file.write Digest::SHA1.hexdigest(bytes) << ' ' << File.basename(pkg) }
      sh 'gpg', '--local-user', gpg_user, '--armor', '--output', pkg + '.asc', '--detach-sig', pkg, :verbose=>true
    end
    cp 'etc/KEYS', 'staged/distro'
  end

  # Publish prerequisites to distro server.
  task 'publish:distro' do |task, args|
    target = args.incubating ? "people.apache.org:/www/www.apache.org/dist/incubator/#{spec.name}/#{spec.version}-incubating" :
      "people.apache.org:/www/www.apache.org/dist/#{spec.name}/#{spec.version}"
    puts 'Uploading packages to Apache distro ...'
    host, remote_dir = target.split(':')
    sh 'ssh', host, 'rm', '-rf', remote_dir rescue nil
    sh 'ssh', host, 'mkdir', remote_dir
    sh 'rsync', '--progress', '--recursive', 'published/distro/', target
    puts 'Done'
  end

  task 'distro-links'=>'staged/distro' do |task, args|
    url = args.incubating ? "http://www.apache.org/dist/incubator/#{spec.name}/#{spec.version}-incubating" :
      "http://www.apache.org/dist/#{spec.name}/#{spec.version}"
    rows = FileList['staged/distro/*.{gem,tgz,zip}'].map { |pkg|
      name, md5 = File.basename(pkg), Digest::MD5.file(pkg).to_s
      %{| "#{name}":#{url}/#{name} | "#{md5}":#{url}/#{name}.md5 | "Sig":#{url}/#{name}.asc |}
    }
    textile = <<-TEXTILE
h3. #{spec.name} #{spec.version}#{args.incubating && "-incubating"} (#{Time.now.strftime('%Y-%m-%d')})

|_. Package |_. MD5 Checksum |_. PGP |
#{rows.join("\n")}

p>. ("Release signing keys":#{url}/KEYS)
    TEXTILE
    file_name = 'doc/pages/download.textile'
    print "Adding download links to #{file_name} ... "
    modified = File.read(file_name).sub(/h2.*binaries.*source.*/i) { |header| "#{header}\n\n#{textile}" }
    File.open file_name, 'w' do |file|
      file.write modified
    end
    puts 'Done'
  end

  file 'staged/site'=>['distro-links', 'staged', 'site'] do
    rm_rf 'staged/site'
    cp_r 'site', 'staged'
  end

  # Publish prerequisites to Web site.
  task 'publish:site' do |task, args|
    target = args.incubating ? "people.apache.org:/www/incubator.apache.org/#{spec.name}" :
      "people.apache.org:/www/#{spec.name}.apache.org"
    puts 'Uploading Apache Web site ...'
    sh 'rsync', '--progress', '--recursive', '--delete', 'published/site/', target
    puts 'Done'
  end
  
  
  file 'release-vote-email.txt'=>'CHANGELOG' do |task|
    # Need to know who you are on Apache, local user may be different (see .ssh/config).
    whoami = `ssh people.apache.org whoami`.strip
    base_url = "http://people.apache.org/~#{whoami}/buildr/#{spec.version}"
    # Need changes for this release only.
    changelog = File.read('CHANGELOG').scan(/(^(\d+\.\d+(?:\.\d+)?)\s+\(\d{4}-\d{2}-\d{2}\)\s*((:?^[^\n]+\n)*))/)
    changes = changelog[0][2]
    previous_version = changelog[1][1]

    email = <<-EMAIL
To: buildr-dev@incubator.apache.org
Subject: [VOTE] Buildr #{spec.version} release

We're voting on the source distributions available here:
#{base_url}/distro/

Specifically:
#{base_url}/distro/buildr-#{spec.version}-incubating.tgz
#{base_url}/distro/buildr-#{spec.version}-incubating.zip

The documentation generated for this release is available here:
#{base_url}/site/
#{base_url}/site/buildr.pdf

The official specification against which this release was tested:
#{base_url}/site/specs.html

Test coverage report:
#{base_url}/site/coverage/index.html


The following changes were made since #{previous_version}:

#{changes}
    EMAIL
    File.open task.name, 'w' do |file|
      file.write email
    end
    puts "Created release vote email template in '#{task.name}':"
    puts email
  end

end

task 'clobber' do
  rm_rf 'snapshot'
  rm_f 'release-vote-email.txt'
end


task 'stage:check'=>['apache:check']
task 'stage:prepare'=>['staged/distro', 'staged/site'] do |task|
  # Since this requires input (passphrase), do it at the very end.
  task.enhance do
    task('apache:sign').invoke
  end
end
task 'stage' do
  task('apache:snapshot').invoke
end
task 'stage:wrapup'=>'release-vote-email.txt'

task 'release:publish'=>['apache:publish:distro', 'apache:publish:site']