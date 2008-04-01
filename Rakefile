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
$spec = $specs[RUBY_PLATFORM =~ /java/ ? 'java' : 'ruby']

$license_excluded = ['lib/core/progressbar.rb', 'spec/spec.opts', 'doc/css/syntax.css', '.textile', '.haml']


# Finds and returns path to executable.  Consults PATH environment variable.
# Returns nil if executable not found.
def which(name)
  if Gem.win_platform?
    path = ENV['PATH'].split(File::PATH_SEPARATOR).map { |path| path.gsub('\\', '/') }.map { |path| "#{path}/#{name}.{exe,bat,com}" }
  else
    path = ENV['PATH'].split(File::PATH_SEPARATOR).map { |path| "#{path}/#{name}" }
  end
  FileList[path].existing.first
end

# Runs Ruby with these command line arguments.  The last argument may be a hash,
# supporting the following keys:
#   :script   -- Runs the specified script (e.g., :script=>'gem')
#   :sudo     -- Run as sudo on operating systems that require it.
#   :verbose  -- Override Rake's verbose flag.
def ruby(*args)
  options = Hash === args.last ? args.pop : {}
  cmd = []
  cmd << 'sudo' if options.delete(:sudo) && !Gem.win_platform?
  cmd << Config::CONFIG['ruby_install_name']
  cmd << '-S' << options.delete(:command) if options[:command]
  sh *cmd.push(*args.flatten).push(options)
end


begin
  require 'highline/import'
rescue LoadError 
  puts 'HighLine required, please run rake setup first'
end

# Setup environment for running this Rakefile (RSpec, Docter, etc).
desc "If you're building from sources, run this task one to setup the necessary dependencies."
task 'setup' do
  installed = Gem::SourceIndex.from_installed_gems
  dependencies = $spec.dependencies
  dependencies << Gem::Dependency.new('win32console', nil) if Gem.win_platform? # Colors for RSpec.
  dependencies.select { |dep| installed.search(dep.name, dep.version_requirements).empty? }.each do |dep|
    puts "Installing #{dep} ..."
    ruby 'install', dep.name, '-v', dep.version_requirements.to_s, :command=>'gem', :sudo=>true
  end
end


namespace 'release' do

  task 'make' do
    task('rubyforge').invoke
    task('apache:upload').invoke('buildr', true)
  end

end
