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

unless defined?(Buildr::VERSION)
  require File.join(File.dirname(__FILE__), 'lib', 'buildr', 'version.rb')
end

Gem::Specification.new do |spec|
  spec.name           = 'buildr'
  spec.version        = Buildr::VERSION.dup
  spec.author         = 'Apache Buildr'
  spec.email          = "users@buildr.apache.org"
  spec.homepage       = "http://buildr.apache.org/"
  spec.summary        = "Build like you code"
  spec.description    = <<-TEXT
Apache Buildr is a build system for Java-based applications, including support
for Scala, Groovy and a growing number of JVM languages and tools.  We wanted
something that's simple and intuitive to use, so we only need to tell it what
to do, and it takes care of the rest.  But also something we can easily extend
for those one-off tasks, with a language that's a joy to use.
  TEXT
  spec.rubyforge_project  = 'buildr'

  # Rakefile needs to create spec for both platforms (ruby and java), using the
  # $platform global variable.  In all other cases, we figure it out from RUBY_PLATFORM.
  spec.platform       = $platform || RUBY_PLATFORM[/java/] || 'ruby'

  spec.files          = Dir['{addon,bin,doc,etc,lib,rakelib,spec}/**/*', '*.{gemspec,buildfile}'] +
                        ['LICENSE', 'NOTICE', 'CHANGELOG', 'README.rdoc', 'Rakefile', '_buildr', '_jbuildr']
  spec.require_paths  = 'lib', 'addon'
  spec.bindir         = 'bin'                               # Use these for applications.
  spec.executable     = 'buildr'

  spec.extra_rdoc_files = 'README.rdoc', 'CHANGELOG', 'LICENSE', 'NOTICE'
  spec.rdoc_options     = '--title', 'Buildr', '--main', 'README.rdoc',
                          '--webcvs', 'http://svn.apache.org/repos/asf/buildr/trunk/'
  spec.post_install_message = "To get started run buildr --help"

  # Tested against these dependencies.
  spec.add_dependency 'rake',                 '0.8.7'
  spec.add_dependency 'builder',              '2.1.2'
  spec.add_dependency 'net-ssh',              '2.0.23'
  spec.add_dependency 'net-sftp',             '2.0.4'
  spec.add_dependency 'rubyzip',              '0.9.4'
  spec.add_dependency 'highline',             '1.5.1'
  spec.add_dependency 'json_pure',            '1.4.3'
  spec.add_dependency 'rubyforge',            '2.0.3'
  spec.add_dependency 'hoe',                  '2.3.3'
  spec.add_dependency 'rjb',                  '1.3.3' if spec.platform.to_s == 'ruby'
  spec.add_dependency 'rjb',                  '1.3.2' if spec.platform.to_s == 'x86-mswin32'
  spec.add_dependency 'atoulme-Antwrap',      '0.7.1'
  spec.add_dependency 'diff-lcs',             '1.1.2'
  spec.add_dependency 'rspec-expectations',   '2.1.0'
  spec.add_dependency 'rspec-mocks',          '2.1.0'
  spec.add_dependency 'rspec-core',           '2.1.0'
  spec.add_dependency 'rspec',                '2.1.0'
  spec.add_dependency 'xml-simple',           '1.0.12'
  spec.add_dependency 'minitar',              '0.5.3'
  spec.add_dependency 'jruby-openssl',        '>= 0.7' if spec.platform.to_s == 'java'
  spec.add_development_dependency 'jekyll', '~> 0.6.2' unless spec.platform.to_s == 'java'
  spec.add_development_dependency 'sdoc'
  spec.add_development_dependency 'rcov', '0.9.9' unless spec.platform.to_s == 'java'
  spec.add_development_dependency 'win32console' if spec.platform.to_s == 'x86-mswin32'
  spec.add_development_dependency 'jekylltask', '>= 1.0.2' unless spec.platform.to_s == 'java'
end
