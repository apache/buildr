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

if !RUBY_PLATFORM[/java/]
  gem 'rdoc'
  require 'rdoc/task'
  desc "Creates a symlink to rake's lib directory to support combined rdoc generation"
  file "rake/lib" do
    rake_path = $LOAD_PATH.find { |p| File.exist? File.join(p, "rake.rb") }
    mkdir_p "rake"
    File.symlink(rake_path, "rake/lib")
  end

  desc "Generate RDoc documentation in rdoc/"
  RDoc::Task.new :rdoc do |rdoc|
    rdoc.rdoc_dir = 'rdoc'
    rdoc.title = spec.name
    rdoc.options = spec.rdoc_options.clone
    rdoc.rdoc_files.include('lib/**/*.rb')
    rdoc.rdoc_files.include spec.extra_rdoc_files

      # include rake source for better inheritance rdoc
    rdoc.rdoc_files.include('rake/lib/**.rb')
  end
  task :rdoc => ["rake/lib"]

  begin
    require 'jekylltask'
    module TocFilter
      def toc(input)
        output = "<ol class=\"toc\">"
        input.scan(/<(h2)(?:>|\s+(.*?)>)([^<]*)<\/\1\s*>/mi).each do |entry|
          id = (entry[1][/^id=(['"])(.*)\1$/, 2] rescue nil)
          title = entry[2].gsub(/<(\w*).*?>(.*?)<\/\1\s*>/m, '\2').strip
          if id
            output << %{<li><a href="##{id}">#{title}</a></li>}
          else
            output << %{<li>#{title}</li>}
          end
        end
        output << "</ol>"
        output
      end
    end
    Liquid::Template.register_filter(TocFilter)

    desc "Generate Buildr documentation in _site/"
    JekyllTask.new :jekyll do |task|
      task.source = 'doc'
      task.target = '_site'
    end

  rescue LoadError
    puts "Buildr uses the jekyll gem to generate the Web site. You can install it by running bundler"
  end

  if 0 == system("pygmentize -V > /dev/null 2> /dev/null")
    puts "Buildr uses the Pygments python library. You can install it by running 'sudo easy_install Pygments' or 'sudo apt-get install python-pygments'"
  end

  desc "Generate Buildr documentation as buildr.pdf"
  file 'buildr.pdf'=>'_site' do |task|
    pages = File.read('_site/preface.html').scan(/<li><a href=['"]([^'"]+)/).flatten.map { |f| "_site/#{f}" }
    sh 'prince', '--input=html', '--no-network', '--log=prince_errors.log', "--output=#{task.name}", '_site/preface.html', *pages
  end

  desc "Build a copy of the Web site in the ./_site"
  task :site=>['_site', :rdoc, '_reports/specs.html', '_reports/coverage', 'buildr.pdf'] do
    cp_r 'rdoc', '_site'
    fail 'No RDocs in site directory' unless File.exist?('_site/rdoc/lib/buildr_rb.html')
    cp '_reports/specs.html', '_site'
    cp_r '_reports/coverage', '_site'
    fail 'No coverage report in site directory' unless File.exist?('_site/coverage/index.html')
    cp 'CHANGELOG', '_site'
    open("_site/.htaccess", "w") do |htaccess|
      htaccess << %Q{
<FilesMatch "CHANGELOG">
ForceType 'text/plain; charset=UTF-8'
</FilesMatch>
}
    end
    cp 'buildr.pdf', '_site'
    fail 'No PDF in site directory' unless File.exist?('_site/buildr.pdf')
    puts 'OK'
  end

# Publish prerequisites to Web site.
  task 'publish'=>:site do
    target = "people.apache.org:/www/#{spec.name}.apache.org/"
    puts "Uploading new site to #{target} ..."
    sh 'rsync', '--progress', '--recursive', '--delete', '_site/', target
    sh 'ssh', 'people.apache.org', 'chmod', '-f', '-R', 'g+w', "/www/#{spec.name}.apache.org/*"
    puts "Done"
  end

# Update HTML + PDF documentation (but not entire site; no specs, coverage, etc.)
  task 'publish-doc' => ['buildr.pdf', '_site'] do
    cp 'buildr.pdf', '_site'
    target = "people.apache.org:/www/#{spec.name}.apache.org/"
    puts "Uploading new site to #{target} ..."
    sh 'rsync', '--progress', '--recursive', '_site/', target # Note: no --delete
    sh 'ssh', 'people.apache.org', 'chmod', '-f', '-R', 'g+w', "/www/#{spec.name}.apache.org/*"
    puts "Done"
  end

  task :clobber do
    rm_rf '_site'
    rm_f 'buildr.pdf'
    rm_f 'prince_errors.log'
  end
end
