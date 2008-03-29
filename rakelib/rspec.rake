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


begin
  require 'spec/rake/spectask'

  desc 'Run all specs'
  Spec::Rake::SpecTask.new('spec') do |task|
    task.spec_files = FileList['spec/**/*_spec.rb']
    task.spec_opts << '--options' << 'spec/spec.opts' << '--format' << 'failing_examples:failing'
  end

  desc 'Run all failing examples from previous run'
  Spec::Rake::SpecTask.new('failing') do |task|
    task.spec_files = FileList['spec/**/*_spec.rb']
    task.spec_opts << '--options' << 'spec/spec.opts' << '--format' << 'failing_examples:failing' << '--example' << 'failing'
  end

  directory 'reports'
  desc 'Run RSpec and generate Spec and coverage reports (slow)'
  Spec::Rake::SpecTask.new('reports') do |task|
    task.spec_files = FileList['spec/**/*_spec.rb']
    task.spec_opts << '--format' << 'html:reports/specs.html' << '--backtrace'
    task.rcov = true
    task.rcov_opts = ['--exclude', 'spec,bin']
  end
  task 'reports' do
    mv 'coverage', 'reports'
  end

  task 'clobber' do
    rm 'failing' rescue nil
    rm_rf 'reports'
  end

rescue LoadError
  say 'Please run rake setup to install RSpec'
  task 'setup' do
    ruby 'install', 'rspec', :command=>'gem', :sudo=>true
  end
  task 'release:check' do
    fail 'Please run rake setup to install RSpec'
  end
end


# Useful for testing with JRuby when using Ruby and vice versa.
namespace 'spec' do
  desc 'Run all specs specifically with Ruby'
  task 'ruby' do
    say 'Running test suite using Ruby ...'
    system 'ruby -S rake spec'
  end

  desc 'Run all specs specifically with JRuby'
  task 'jruby' do
    say 'Running test suite using JRuby ...'
    system 'jruby -S rake spec'
  end
end

namespace 'release' do
  # Full test suite depends on having JRuby, Scala and Groovy installed.
  task 'check' do
    say 'Checking that we have JRuby, Scala and Groovy available ... '
    fail 'Full testing requires JRuby!' unless which('jruby')
    fail 'Full testing requires Scala!' unless which('scala')
    fail 'Full testing requires Groovy!' unless which('groovy')
    say 'OK'
  end

  # Release requires RSpec and test coverage reports, uploaded as part of site.
  # Primary test environment is Ruby (RCov), also test on JRuby.
  task 'prepare'=>['compile', 'reports', 'spec:jruby'] do
    say 'Checking that we have specs and coverage report ... '
    fail 'No specifications in site directory!' unless File.exist?('site/specs.html') 
    fail 'No coverage reports in site directory!' unless File.exist?('site/coverage/index.html')
    say 'OK'
  end
end
