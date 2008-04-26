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


require 'md5'
require 'sha1'


# Tasks specific to Apache projects (license, release, etc).
namespace 'apache' do

  desc 'Check that source files contain the Apache license'
  task 'license' do |task|
    print 'Checking that files contain the Apache license ... '
    required = task.prerequisites.select { |fn| File.file?(fn) }
    missing = required.reject { |fn| 
      comments = File.read(fn).scan(/(\/\*(.*?)\*\/)|^#\s+(.*?)$|<!--(.*?)-->/m).
        map { |match| match.compact }.flatten.join("\n")
      comments =~ /Licensed to the Apache Software Foundation/ && comments =~ /http:\/\/www.apache.org\/licenses\/LICENSE-2.0/
    }
    fail "#{missing.join(', ')} missing Apache License, please add it before making a release!" unless missing.empty?
    puts 'OK'
  end
  task('license').prerequisites.exclude('.class', '.png', '.jar', '.tif', '.textile', '.haml',
    'README', 'LICENSE', 'CHANGELOG', 'DISCLAIMER', 'NOTICE', 'KEYS', 'spec/spec.opts')

  task 'check' do
    ENV['GPG_USER'] or fail 'Please set GPG_USER (--local-user) environment variable so we know which key to use.'
  end


  file 'staged/distro'=>'package' do
    puts 'Copying and signing release files ...'
    mkpath 'staged/distro'
    FileList['pkg/*.{gem,zip,tgz}'].each do |pkg|
      cp pkg, pkg.pathmap('staged/distro/%n-incubating%x') 
    end
  end

  task 'sign'=>['KEYS', 'staged/distro'] do
    gpg_user = ENV['GPG_USER'] or fail 'Please set GPG_USER (--local-user) environment variable so we know which key to use.'
    FileList['staged/distro/*.{gem,zip,tgz}'].each do |pkg|
      bytes = File.open(pkg, 'rb') { |file| file.read }
      File.open(pkg + '.md5', 'w') { |file| file.write MD5.hexdigest(bytes) << ' ' << File.basename(pkg) }
      File.open(pkg + '.sha1', 'w') { |file| file.write SHA1.hexdigest(bytes) << ' ' << File.basename(pkg) }
      sh 'gpg', '--local-user', gpg_user, '--armor', '--output', pkg + '.asc', '--detach-sig', pkg, :verbose=>true
    end
    cp 'KEYS', 'staged/distro'
  end

  # Publish prerequisites to distro server.
  task 'publish:distro' do |task, args|
    target = args.incubating ? "people.apache.org:/www/www.apache.org/dist/incubator/#{spec.name}/#{spec.version}-incubating" :
      "people.apache.org:/www/www.apache.org/dist/#{spec.name}/#{spec.version}"
    puts 'Uploading packages to Apache distro ...'
    sh 'rsync', '--progress', 'published/distro/*', target
    puts 'Done'
  end

  task 'add-links' do |task, args|
    url = args.incubating ? "http://www.apache.org/dist/incubator/#{spec.name}/#{spec.version}-incubating" :
      "http://www.apache.org/dist/#{spec.name}/#{spec.version}"
    links = FileList['staged/distro/*.{gem,tgz,zip}'].map { |pkg|
      name = File.basename(pkg)
      md5 = File.read("#{pkg}.md5").split.first
      %{| "#{name}":#{url}/#{name} | "#{md5}":#{url}/#{name}.md5 | "PGP":#{url}/#{name}.asc |}
    }
    textile = <<-TEXTILE
h3. #{spec.name} #{spec.version}-incubating

|_. Package |_. MD5 Checksum |_. Signature |
#{links.join("\n")}

p>.  ("Signing keys":#{url}/KEYS)
    TEXTILE
    fn = 'doc/pages/download.textile'
    modified = File.read(fn).sub(/^h2.*binaries.*source.*$/i) { |header| "#{header}\n\n#{textile}" }
    File.open fn, 'w' do |file|
      file.write modified
    end
  end


  file 'staged/site'=>'site' do
    mkpath 'staged'
    rm_rf 'staged/site'
    cp_r 'site', 'staged'
  end

  # Publish prerequisites to Web site.
  task 'publish:site' do |task, args|
    target = args.incubating ? "people.apache.org:/www/incubator.apache.org/#{spec.name}" :
      "people.apache.org:/www/#{spec.name}.apache.org"
    puts 'Uploading Apache Web site ...'
    sh 'rsync', '--progress', '--recursive', '--delete', 'published/distro/site/', target
    puts 'Done'
  end

end


task 'stage:check'=>['apache:license', 'apache:check']
task 'stage:prepare'=>['staged/distro', 'staged/site'] do |task|
  # Since this requires input (passphrase), do it at the very end.
  task.enhance do
    task('apache:sign').invoke
  end
end
task 'release:publish'=>['apache:publish:distro', 'apache:publish:site']
