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


begin # For the Web site, we use the mislav-hanna RDoc theme (http://github.com/mislav/hanna/)
  require 'hanna/rdoctask'
rescue LoadError
  puts "Buildr uses the mislav-hanna RDoc theme. You can install it by running rake setup"
  task('setup') { install_gem 'mislav-hanna', :source=>'http://gems.github.com' }
  require 'rake/rdoctask'
end


desc 'Generate RDoc documentation'
rdoc = Rake::RDocTask.new('rdoc') do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = spec.name
  rdoc.options  = spec.rdoc_options.clone
  rdoc.rdoc_files.include('lib/**/*.rb')
  rdoc.rdoc_files.include spec.extra_rdoc_files
end


begin
  require 'jekyll'

  class Albino
    def execute(command)
      output = ''
      Open4.popen4(command) do |pid, stdin, stdout, stderr|
        stdin.puts @target
        stdin.close
        output = stdout.read.strip
        [stdout, stderr].each { |io| io.close }
      end
      output
    end
  end

  task '_site'=>['doc'] do
    Jekyll.pygments = true
    Jekyll.process 'doc', '_site'
  end

rescue LoadError
  puts "Buildr uses the mojombo-jekyll to generate the Web site. You can install it by running rake setup"
  task 'setup' do
    install_gem 'mojombo-jekyll', :source=>'http://gems.github.com', :version=>'0.4.1'
    sh "#{sudo_needed? ? 'sudo ' : nil}easy_install Pygments"
  end
end


desc "Build a copy of the Web site in the ./_site"
task 'site'=>['_site', 'rdoc', 'spec', 'coverage'] do
  cp_r 'rdoc', '_site'
  fail 'No RDocs in site directory' unless File.exist?('_site/rdoc/files/lib/buildr_rb.html')
  cp '_reports/specs.html', '_site'
  cp_r '_reports/coverage', '_site'
  fail 'No coverage report in site directory' unless File.exist?('_site/coverage/index.html')
  puts 'OK'
end


# Publish prerequisites to Web site.
task 'site_publish'=>'site' do
  target = "people.apache.org:/www/#{spec.name}.apache.org"
  puts "Uploading new site to #{target} ..."
  sh "rsync --progress --recursive --delete _site/ #{target.inspect}/"
  sh "ssh people.apache.org chmod -R g+w /www/#{spec.name}.apache.org/*"
  puts "Done"
end

task 'clobber' do
  rm_rf '_site' if File.exist?('_site')
end
