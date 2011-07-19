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
  require 'rspec/core/rake_task'
  directory '_reports'

  def default_spec_opts
    default = %w{--format documentation --out _reports/specs.txt --backtrace}
    default << '--colour' if $stdout.isatty && !(Config::CONFIG['host_os'] =~ /mswin|win32|dos/i)
    default
  end

  # RSpec doesn't support file exclusion, so hack our own.
  class RSpec::Core::RakeTask
    attr_accessor :rspec_files
  private
    def files_to_run
      @rspec_files
    end
  end

  desc "Run all specs"
  RSpec::Core::RakeTask.new :spec=>['_reports', :compile] do |task|
    ENV['USE_FSC'] = 'no'
    task.rspec_files = FileList['spec/**/*_spec.rb']
    task.rspec_files.exclude('spec/groovy/*') if RUBY_PLATFORM[/java/]
    task.rspec_opts = default_spec_opts
    task.rspec_opts = %w{--format html --out _reports/specs.html --backtrace}
  end
  file('_reports/specs.html') { task(:spec).invoke }

  desc 'Run RSpec and generate Spec and coverage reports (slow)'
  RSpec::Core::RakeTask.new :coverage=>['_reports', :compile] do |task|
    ENV['USE_FSC'] = 'no'
    task.rspec_files = FileList['spec/**/*_spec.rb']
    task.rspec_files.exclude('spec/groovy/*') if RUBY_PLATFORM[/java/]
    task.rspec_opts = default_spec_opts
    task.rcov = true
    task.rcov_opts = %w{-o _reports/coverage --exclude / --include-file ^lib --text-summary}
  end
  file('_reports/coverage') { task(:coverage).invoke }

  task :load_ci_reporter do
    gem 'ci_reporter'
    ENV['CI_REPORTS'] = '_reports/ci'
    # CI_Reporter does not quote the path to rspec_loader which causes problems when ruby is installed in C:/Program Files.
    # However, newer versions of rspec don't like double quotes escaping as well, so removing them for now.
    ci_rep_path = Gem.loaded_specs['ci_reporter'].full_gem_path
    ENV["SPEC_OPTS"] = [ENV["SPEC_OPTS"], default_spec_opts, "--require", "#{ci_rep_path}/lib/ci/reporter/rake/rspec_loader.rb", "--format", "CI::Reporter::RSpec"].join(" ")
  end

  desc 'Run all specs with CI reporter'
  task :ci=>[:load_ci_reporter, :spec]

  # Useful for testing with JRuby when using Ruby and vice versa.
  namespace :spec do
    desc "Run all specs specifically with Ruby"
    task :ruby do
      puts "Running test suite using Ruby ..."
      sh 'ruby -S rake spec'
    end

    desc "Run all specs specifically with JRuby"
    task :jruby do
      puts "Running test suite using JRuby ..."
      sh 'jruby -S rake spec'
    end
  end

  task :clobber do
    rm_f 'failed'
    rm_rf '_reports'
  end

rescue LoadError => e
  puts "Buildr uses RSpec. You can install it by running bundler"
end
