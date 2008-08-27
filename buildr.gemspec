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


Gem::Specification.new do |spec|
  spec.name           = 'buildr'
  spec.version        = '1.3.3'
  spec.author         = 'Apache Buildr'
  spec.email          = "buildr-user@incubator.apache.org"
  spec.homepage       = "http://incubator.apache.org/buildr"
  spec.summary        = 'A build system that doesn\'t suck'
  spec.rubyforge_project  = 'buildr'

  # Rakefile needs to create spec for both platforms (ruby and java), using the
  # $platform global variable.  In all other cases, we figure it out from RUBY_PLATFORM.
  spec.platform       = $platform || RUBY_PLATFORM[/java/] || 'ruby'
  
  spec.files          = Dir['lib/**/*', 'bin/**/*', 'addon/**/*', 'doc/**/*', 'spec/**/*',
                            'README.rdoc', 'LICENSE', 'NOTICE', 'DISCLAIMER', 'CHANGELOG',
                            'buildr.*', 'Rakefile', 'rakelib/**/*', '_buildr', 'etc/**/*']
  spec.require_paths  = ['lib', 'addon']
  spec.bindir         = 'bin'                               # Use these for applications.
  spec.executable     = 'buildr'

  spec.has_rdoc         = true
  spec.extra_rdoc_files = ['README.rdoc', 'CHANGELOG', 'LICENSE', 'NOTICE', 'DISCLAIMER']
  spec.rdoc_options     << '--title' << "Buildr" << '--main' << 'README.rdoc' <<
                           '--line-numbers' << '--inline-source' << '-p' <<
                           '--webcvs' << 'http://svn.apache.org/repos/asf/incubator/buildr/trunk/'

  # Tested against these dependencies.
  spec.add_dependency 'rake',                 '0.8.1'
  spec.add_dependency 'builder',              '2.1.2'
  spec.add_dependency 'net-ssh',              '2.0.3'
  spec.add_dependency 'net-sftp',             '2.0.1'
  spec.add_dependency 'rubyzip',              '0.9.1'
  spec.add_dependency 'highline',             '1.4.0'
  spec.add_dependency 'rubyforge',            '1.0.0'
  spec.add_dependency 'hoe',                  '1.6.0'
  spec.add_dependency 'rjb',                  '1.1.6' if spec.platform.to_s == 'ruby' 
  spec.add_dependency 'Antwrap',              '0.7.0'
  spec.add_dependency 'rspec',                '1.1.4'
  spec.add_dependency 'xml-simple',           '1.0.11'
  spec.add_dependency 'archive-tar-minitar',  '0.5.2'
  spec.add_dependency 'jruby-openssl',        '0.2'   if spec.platform.to_s == 'java'
  spec.add_dependency 'ci_reporter',          '1.5.1' if spec.platform.to_s == 'java'
end