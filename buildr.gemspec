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
  spec.version        = '1.3.0'
  spec.author         = 'Apache Buildr'
  spec.email          = "#{spec.name}-user@incubator.apache.org"
  spec.homepage       = "http://incubator.apache.org/#{spec.name}/"
  spec.summary        = 'A build system that doesn\'t suck'

  spec.files          = FileList['lib/**/*', 'addon/**/*', 'README', 'CHANGELOG', 'LICENSE', 'NOTICE', 'DISCLAIMER', 'KEYS',
                                 '*.gemspec', 'Rakefile', 'rakelib/**/*', 'spec/**/*', 'doc/**/*'].to_ary
  spec.require_paths  = ['lib', 'addon']
  spec.bindir         = 'bin'                               # Use these for applications.
  spec.executable     = 'buildr'

  spec.has_rdoc           = true
  spec.extra_rdoc_files   = ['README', 'CHANGELOG', 'LICENSE', 'NOTICE', 'DISCLAIMER']
  spec.rdoc_options       << '--title' << "Buildr -- #{spec.summary}" <<
                             '--main' << 'README' << '--line-numbers' << '--inline-source' << '-p' <<
                             '--webcvs' << 'http://svn.apache.org/repos/asf/incubator/#{spec.name}/trunk/'
  spec.rubyforge_project  = 'buildr'

  # Tested against these dependencies.
  spec.add_dependency 'rake',                 '~> 0.8'
  spec.add_dependency 'builder',              '~> 2.1'
  spec.add_dependency 'net-ssh',              '~> 2.0'
  spec.add_dependency 'net-sftp',             '~> 2.0'
  spec.add_dependency 'rubyzip',              '~> 0.9'
  spec.add_dependency 'highline',             '~> 1.4'
  spec.add_dependency 'Antwrap',              '~> 0.7'
  spec.add_dependency 'rspec',                '~> 1.1'
  spec.add_dependency 'xml-simple',           '~> 1.0'
  spec.add_dependency 'archive-tar-minitar',  '~> 0.5'
  spec.add_dependency 'rubyforge',            '~> 0.4'
end
