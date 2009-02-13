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


require 'rake/rdoctask'

desc 'Generate RDoc documentation'
rdoc = Rake::RDocTask.new('rdoc') do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = spec.name
  rdoc.options  = spec.rdoc_options + ['--promiscuous']
  rdoc.rdoc_files.include('lib/**/*.rb')
  rdoc.rdoc_files.include spec.extra_rdoc_files
end


begin
  gem 'allison'
  rdoc.template = File.expand_path('lib/allison.rb', Gem.loaded_specs['allison'].full_gem_path)
rescue LoadError
  puts 'Please run rake setup to install the Allison RDoc template'
  task 'setup' do
    install_gem 'allison'
  end
  task 'stage:check' do
    fail 'Please run rake setup to install the Allison RDoc template'
  end
end


begin
  require 'docter'
  require 'docter/server'

  #Docter.filter_for(:footnote) do |html|
  #  html.gsub(/<p id="fn(\d+)">(.*?)<\/p>/, %{<p id="fn\\1" class="footnote">\\2</p>})
  #end

  collection = Docter.collection(spec.name).using('doc/site.toc.yaml').include('doc/pages', 'LICENSE', 'CHANGELOG')
  # TODO:  Add coverage reports when we get them to run.
  template   = Docter.template('doc/site.haml').include('doc/css', 'doc/images', 'doc/scripts', 'rdoc')

  desc 'Run Docter server on port 3000'
  Docter::Rake.serve 'docter', collection, template, :port=>3000

  Docter::Rake.generate '_print',
    Docter.collection(spec.name).using('doc/print.toc.yaml').include('doc/pages'),
    Docter.template('doc/print.haml').include('doc/css', 'doc/images'), :one_page

  file('buildr.pdf'=>'_print') do |task|
    sh 'prince', '_print/index.html', '-o', task.name, '--media=print' do |ok, res|
      fail 'Failed to create PDF, see errors above' unless ok
    end
  end

  desc 'Generate Web site in directory site'
  Docter::Rake.generate '_site', collection, template

  task '_site/buildr.pdf'=>'buildr.pdf' do
    cp 'buildr.pdf', '_site'
  end
  task '_site/specs.html'=>'_reports/specs.html' do
    cp '_reports/specs.html', '_site'
  end
  task '_site/coverage'=>'_reports/coverage' do
    cp '_reports/coverage', '_site'
  end

  task 'site'=>['_site', '_site/buildr.pdf', '_site/specs.html', '_site/coverage'] do
    print 'Checking that we have site documentation, RDoc and PDF ... '
    fail 'No PDF generated, you need to install PrinceXML!' unless File.exist?('_site/buildr.pdf')
    fail 'No RDocs in site directory' unless File.exist?('_site/rdoc/files/lib/buildr_rb.html')
    fail 'No site documentation in site directory' unless File.exist?('_site/index.html')
    fail 'No specifications in site directory' unless File.exist?('_site/specs.html')
    fail 'No coverage report in site directory' unless File.exist?('_site/coverage')
    puts 'OK'
  end

  desc 'Produce PDF'
  task 'pdf'=>'_print/buildr.pdf' do |task|
    sh 'open', '_print/buildr.pdf'
  end

  task 'clobber' do
    rm_rf '_site'
    rm_rf '_print'
    rm_rf 'buildr.pdf'
  end

rescue LoadError
  puts 'Please run rake setup to install the Docter document generation library'
  task 'setup' do
    install_gem 'docter', '~>1.1.3'
  end
  task 'stage:check' do
    fail 'Please run rake setup to install the Docter document generation library'
  end
end
