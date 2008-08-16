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

  directory 'reports'
  task 'clobber' do
    rm_r 'failed'
    rm_rf 'reports'
  end

  desc 'Run all specs'
  Spec::Rake::SpecTask.new('spec'=>'reports') do |task|
    task.spec_files = FileList['spec/**/*_spec.rb']
    task.spec_opts << '--options' << 'spec/spec.opts' << '--format' << 'failing_examples:failed' <<
      '--format' << 'html:reports/specs.html' << '--backtrace'
  end
  file 'reports/specs.html'=>'spec'

  desc 'Run all failed examples from previous run'
  Spec::Rake::SpecTask.new('failed') do |task|
    task.spec_files = FileList['spec/**/*_spec.rb']
    task.spec_opts << '--options' << 'spec/spec.opts' << '--format' << 'failing_examples:failed' << '--example' << 'failed'
  end

  # TODO: Horribly broken!  Fix some other time.
  desc 'Run RSpec and generate Spec and coverage reports (slow)'
  Spec::Rake::SpecTask.new('rcov') do |task|
    task.spec_files = FileList['spec/**/*spec.rb']
    task.spec_opts '--format' << 'html:reports/specs.html' << '--backtrace'
    task.rcov = true
    task.rcov_dir = 'reports/coverage'
    task.rcov_opts << '--exclude' << "spec,bin,#{Config::CONFIG['sitedir']},#{Gem.path.join(',')}"
    task.rcov_opts << '--text-summary'
  end
  file 'reports/coverage'=>'rcov'

  # Useful for testing with JRuby when using Ruby and vice versa.
  namespace 'spec' do

    desc 'Run all specs specifically with Ruby'
    task 'ruby' do
      puts 'Running test suite using Ruby ...'
      sh 'ruby -S rake spec'
    end

    desc 'Run all specs specifically with JRuby'
    task 'jruby' do
      puts 'Running test suite using JRuby ...'
      sh 'jruby -S rake spec'
    end

  end

  task 'setup' do
    install_gem 'win32console' if Gem.win_platform? # Colors for RSpec, only on Windows platform.
  end

rescue LoadError
  puts 'Please run rake setup to install RSpec'
  task 'stage:check' do
    fail 'Please run rake setup to install RSpec'
  end
end


task 'stage:prepare'=>'spec'
task 'stage:prepare'=>RUBY_PLATFORM =~ /java/ ? 'spec:ruby' : 'spec:jruby'
# TODO:  Add Rcov when we get it working again.
