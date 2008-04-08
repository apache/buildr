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
# True if running on the Windows operating sytem.  Different from Gem.win_platform?
# which returns true if running on the Windows platform of MRI, false when using JRuby.


def windows?
  Config::CONFIG['host_os'] =~ /windows|cygwin|bccwin|cygwin|djgpp|mingw|mswin|wince/i
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


def install_gem(name, ver_requirement = nil)
  dep = Gem::Dependency.new(name, ver_requirement)
  if Gem::SourceIndex.from_installed_gems.search(dep).empty? 
    puts "Installing #{name} #{ver_requirement} ..."
    args = [Config::CONFIG['ruby_install_name'], '-S', 'gem', 'install', name]
    args.unshift('sudo') unless windows?
    args << '-v' << ver_requirement.to_s if ver_requirement
    sh *args
  end
end

# Setup environment for running this Rakefile (RSpec, Docter, etc).
desc "If you're building from sources, run this task one to setup the necessary dependencies."
missing = spec.dependencies.select { |dep| Gem::SourceIndex.from_installed_gems.search(dep).empty? }
task 'setup' do
  missing.each do |dep|
    install_gem dep.name, dep.version_requirements
  end
end
puts "Missing Gems #{missing.join(', ')}, please run rake setup first!" unless missing.empty?
