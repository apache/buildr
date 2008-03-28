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
  task 'license' do
    say 'Checking that files contain the Apache license ... '
    excluded = ['.class', '.png', '.jar', '.tif', 'README', 'LICENSE', 'CHANGELOG', 'DISCLAIMER', 'NOTICE', 'KEYS']
    required = FileList[$spec.files].exclude(*excluded).exclude(*Array($license_excluded)).select { |fn| File.file?(fn) }
    missing = required.reject { |fn| 
      comments = File.read(fn).scan(/(\/\*(.*?)\*\/)|^#\s+(.*?)$|<!--(.*?)-->/m).
        map { |match| match.compact }.flatten.join("\n")
      comments =~ /Licensed to the Apache Software Foundation/ && comments =~ /http:\/\/www.apache.org\/licenses\/LICENSE-2.0/
    }
    fail "#{missing.join(', ')} missing Apache License, please add it before making a release!" unless missing.empty?
    say 'OK'
  end

  file 'incubating'=>'package' do
    rm_rf 'incubating'
    mkpath 'incubating'
    say 'Creating -incubating packages ... '
    packages = FileList['pkg/*.{gem,zip,tgz}'].map do |package|
      package.pathmap('incubating/%n-incubating%x').tap do |incubating|
        cp package, incubating
      end
    end
    say 'Done'
  end

  task 'sign', :incubating do |task, args|
    file('incubating').invoke if args.incubating
    sources = FileList[args.incubating ? 'incubating/*' : 'pkg/*']

    gpg_user = ENV['GPG_USER'] or fail 'Please set GPG_USER (--local-user) environment variable so we know which key to use.'
    say 'Signing release files ...'
    sources.each do |fn|
      contents = File.open(fn, 'rb') { |file| file.read }
      File.open(fn + '.md5', 'w') { |file| file.write MD5.hexdigest(contents) << ' ' << File.basename(fn) }
      File.open(fn + '.sha1', 'w') { |file| file.write SHA1.hexdigest(contents) << ' ' << File.basename(fn) }
      sh 'gpg', '--local-user', gpg_user, '--armor', '--output', fn + '.asc', '--detach-sig', fn, :verbose=>true
    end
    say 'Done'
  end

  task 'upload', :project, :incubating, :depends=>['site', 'KEYS', 'sign'] do |task, args|
    fail 'No project specified' unless project

    target = 'people.apache.org:/www.apache.org/dist/'
    target << 'incubator/' if args.incubating
    target << "#{project}/"

    dir = task('sign').prerequisite.find { |prereq| File.directory?(prereq.name) }
    fail 'Please enhance sign task with directory containing files to release' unless dir
    say 'Uploading packages to Apache dist ...'
    args = FileList["#{dir}/*", 'KEYS'].flatten << target
    
    sh 'rsync', '-progress', *args
    say 'Done'
  end

end


task 'clobber' do
  rm_rf 'incubating'
end

namespace 'release' do
  task 'check'=>'apache:license'
end
