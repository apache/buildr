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


require 'rake/gempackagetask'


desc 'Clean up all temporary directories used for running tests, creating documentation, packaging, etc.'
task 'clobber'

package = Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = true
  pkg.need_zip = true
end

desc 'Install the package locally'
task 'install'=>['setup', "#{package.package_dir}/#{package.gem_file}"] do |task|
  print "Installing #{spec.name} ... "
  args = [Config::CONFIG['ruby_install_name'], '-S', 'gem', 'install', "#{package.package_dir}/#{package.gem_file}"]
  args.unshift('sudo') if sudo_needed?
  sh *args
  puts 'Done'
end

desc 'Uninstall previously installed packaged'
task 'uninstall' do |task|
  print "Uninstalling #{spec.name} ... "
  args = [Config::CONFIG['ruby_install_name'], '-S', 'gem', 'uninstall', spec.name, '--version', spec.version.to_s]
  args.unshift('sudo') if sudo_needed?
  sh *args
  puts 'Done'
end


desc 'Look for new dependencies, check transitive dependencies'
task 'dependency' do
  # Find if anything has a more recent dependency.  These are not errors, just reports.
  for dep in spec.dependencies
    current = Gem::SourceInfoCache.search(dep, true, true).last
    latest = Gem::SourceInfoCache.search(Gem::Dependency.new(dep.name, '>0'), true, true).last
    puts "A new version of #{dep.name} is available, #{latest.version} replaces #{current.version}" if latest.version > current.version
  end

  # Returns orderd list of transitive dependencies for the given dependency.
  transitive = lambda { |depend|
    dep_spec = Gem::SourceIndex.from_installed_gems.search(depend).last
    dep_spec.dependencies.map { |trans| transitive[trans].push(trans) }.flatten.uniq }
  # For each dependency, make sure *all* its transitive dependencies are listed
  # as a Buildr dependency, and order is preserved.
  spec.dependencies.each_with_index do |dep, index|
    puts "checking #{dep.name}"
    for trans in transitive[dep]
      matching = spec.dependencies.find { |existing| trans =~ existing }
      fail "#{trans} required by #{dep} and missing from spec" unless matching
      fail "#{trans} must come before #{dep} in dependency list" unless spec.dependencies.index(matching) < index
    end
  end
end

task 'stage:check'=>'dependency'
