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

def spec(platform = nil)
  @specs ||= {}
  platform ||= RUBY_PLATFORM =~ /java/ ? 'java' : 'ruby'
  @specs[platform] ||= begin
    spec = Gem::Specification.load(File.join(File.dirname(__FILE__), 'buildr.gemspec'))
    spec.platform = platform
    if platform =~ /java/
      spec.add_dependency 'jruby-openssl', '0.2'
      spec.add_dependency 'ci_reporter', '1.5.1' # must come after builder dependency
    else
      # Place first on the dependency list, otherwise AntWrap picks the latest RJB.
      spec.dependencies.unshift Gem::Dependency.new('rjb', '1.1.4')
    end
    spec
  end
end


desc 'Compile Java libraries used by Buildr'
task 'compile' do
  puts 'Compiling Java libraries ...'
  sh Config::CONFIG['ruby_install_name'], '-Ilib', '-Iaddon', 'bin/buildr', 'compile'
  puts 'OK'
end
file Rake::GemPackageTask.new(spec).package_dir=>'compile'
file Rake::GemPackageTask.new(spec).package_dir_path=>'compile'

# We also need the other package (JRuby if building on Ruby, and vice versa)
Rake::GemPackageTask.new spec(RUBY_PLATFORM =~ /java/ ? 'ruby' : 'java') do |task|
  # Block necessary otherwise doesn't do full job.
end


ENV['incubating'] = 'true'
ENV['staging'] = "people.apache.org:~/public_html/#{spec.name}/#{spec.version}"

task 'apache:license'=>spec.files
#task('apache:license').prerequisites.exclude( ..not ASL.. )

task 'spec:check' do
  print 'Checking that we have JRuby, Scala and Groovy available ... '
  fail 'Full testing requires JRuby!' unless which('jruby')
  fail 'Full testing requires Scala!' unless which('scala')
  fail 'Full testing requires Groovy!' unless which('groovy')
  puts 'OK'
end


