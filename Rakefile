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

# Load file/system utilities used shared between Buildr's runtime and this Rakefile
require File.expand_path('lib/buildr/core/util', File.dirname(__FILE__))
extend Buildr::SystemUtil

# We need two specifications, for Ruby and Java, and one for the platform we run on.
$specs = ['ruby', 'java'].inject({}) { |hash, platform|
  spec = Gem::Specification.new do |spec|
    spec.name           = 'buildr'
    spec.version        = File.read(__FILE__.pathmap('%d/lib/buildr.rb')).scan(/VERSION\s*=\s*(['"])(.*)\1/)[0][1]
    spec.author         = 'Apache Buildr'
    spec.email          = 'buildr-user@incubator.apache.org'
    spec.homepage       = "http://incubator.apache.org/#{spec.name}/"
    spec.summary        = 'A build system that doesn\'t suck'

    spec.files          = FileList['lib/**/*', 'addon/**/*', 'README', 'CHANGELOG', 'LICENSE', 'NOTICE', 'DISCLAIMER', 'KEYS',
                                   'Rakefile', 'rakelib/**/*', 'spec/**/*', 'doc/**/*'].to_ary
    spec.require_paths  = ['lib', 'addon']
    spec.bindir         = 'bin'                               # Use these for applications.
    spec.executable     = 'buildr'

    spec.has_rdoc           = true
    spec.extra_rdoc_files   = ['README', 'CHANGELOG', 'LICENSE', 'NOTICE', 'DISCLAIMER']
    spec.rdoc_options       << '--title' << "Buildr -- #{spec.summary}" <<
                               '--main' << 'README' << '--line-numbers' << '--inline-source' << '-p' <<
                               '--webcvs' << 'http://svn.apache.org/repos/asf/incubator/buildr/trunk/'
    spec.rubyforge_project  = 'buildr'

    spec.platform  = platform
    # Tested against these dependencies.
    spec.add_dependency 'rake',                 '~> 0.8'
    spec.add_dependency 'builder',              '~> 2.1'
    spec.add_dependency 'net-ssh',              '~> 1.1'
    spec.add_dependency 'net-sftp',             '~> 1.1'
    spec.add_dependency 'rubyzip',              '~> 0.9'
    spec.add_dependency 'highline',             '~> 1.4'
    spec.add_dependency 'Antwrap',              '~> 0.7'
    spec.add_dependency 'rspec',                '~> 1.1'
    spec.add_dependency 'xml-simple',           '~> 1.0'
    spec.add_dependency 'archive-tar-minitar',  '~> 0.5'
    spec.add_dependency 'rubyforge',            '~> 0.4'
    spec.add_dependency 'rjb',                  '~> 1.1' if platform =~ /ruby/
  end
  hash.update(platform=>spec)
}
$spec = $specs[java_platform? ? 'java' : 'ruby']

$license_excluded = ['lib/core/progressbar.rb', 'spec/spec.opts', 'doc/css/syntax.css', '.textile', '.haml']

begin
  require 'highline/import'
rescue LoadError 
  puts 'HighLine required, please run rake setup first'
end

# Setup environment for running this Rakefile (RSpec, Docter, etc).
desc "If you're building from sources, run this task one to setup the necessary dependencies."
task 'setup' do
  dependencies = $spec.dependencies
  dependencies << Gem::Dependency.new('win32console', nil) if Gem.win_platform? # Colors for RSpec.
  install_gems(*dependencies)
end

namespace 'release' do

  task 'make' do
    task('rubyforge').invoke
    task('apache:upload').invoke('buildr', true)
  end

end
