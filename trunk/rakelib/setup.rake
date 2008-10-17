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


require 'rubygems/source_info_cache'
require 'stringio' # for Gem::RemoteFetcher
require 'jruby' if RUBY_PLATFORM[/java/]

# True if running on the Windows operating sytem.  Different from Gem.win_platform?
# which returns true if running on the Windows platform of MRI, false when using JRuby.
def windows?
  Config::CONFIG['host_os'] =~ /windows|cygwin|bccwin|cygwin|djgpp|mingw|mswin|wince/i
end

def set_java_home
  if !ENV['JAVA_HOME'] && RUBY_PLATFORM[/java/]
    ENV['JAVA_HOME'] = java.lang.System.getProperty('java.home')
  end
  fail "Please set JAVA_HOME first #{'(no need to run as sudo)' if ENV['USER'] == 'root'}" unless ENV['JAVA_HOME']
end

def set_gem_home
  ENV['GEM_HOME'] ||= Gem.path.find { |f| File.writable?(f) }
end

def sudo_needed?
  !( windows? || ENV['GEM_HOME'] )
end

# Finds and returns path to executable.  Consults PATH environment variable.
# Returns nil if executable not found.
def which(name)
  if windows?
    path = ENV['PATH'].split(File::PATH_SEPARATOR).map { |path| path.gsub('\\', '/') }.map { |path| "#{path}/#{name}.{exe,bat,com}" }
  else
    path = ENV['PATH'].split(File::PATH_SEPARATOR).map { |path| "#{path}/#{name}" }
  end
  FileList[path].existing.first
end

# Execute a GemRunner command
def gem_run(*args)
  rb_bin = File.join(Config::CONFIG['bindir'], Config::CONFIG['ruby_install_name'])
  args.unshift rb_bin, '-S', 'gem'
  args.unshift 'sudo', 'env', 'JAVA_HOME=' + ENV['JAVA_HOME'] if sudo_needed?
  sh *args.map{ |a| a.inspect }.join(' ')
end

def install_gem(name, ver_requirement = ['> 0'])
  dep = Gem::Dependency.new(name, ver_requirement)
  @load_cache = true
  if Gem::SourceIndex.from_installed_gems.search(dep).empty?
    spec = Gem::SourceInfoCache.search(dep, true, @load_cache).last
    fail "#{dep} not found in local or remote repository!" unless spec
    puts "Installing #{spec.full_name} ..."
    args = ['install']
    args.push '--install-dir', ENV['GEM_HOME'] if ENV['GEM_HOME']
    args.push spec.name, '-v', spec.version.to_s
    gem_run *args
    @load_cache = false # Just update the Gem cache once
  end
end

# Setup environment for running this Rakefile (RSpec, Docter, etc).
desc "If you're building from sources, run this task first to setup the necessary dependencies."
missing = spec.dependencies.select { |dep| Gem::SourceIndex.from_installed_gems.search(dep).empty? }
task 'setup' do
  set_java_home
  set_gem_home
  missing.each do |dep|
    install_gem dep.name, dep.version_requirements
  end
end
puts "Missing Gems #{missing.join(', ')}, please run rake setup first!" unless missing.empty?
