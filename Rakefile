require 'rubygems'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'spec/rake/spectask'


# Gem specification comes first, other tasks rely on it.
def specify(platform)
  Gem::Specification.new do |spec|
    spec.name         = 'buildr'
    spec.version      = File.read(__FILE__.pathmap('%d/lib/buildr.rb')).scan(/VERSION\s*=\s*(['"])(.*)\1/)[0][1]
    spec.author       = 'Apache Buildr'
    spec.email        = 'buildr-user@incubator.apache.org'
    spec.homepage     = "http://incubator.apache.org/#{spec.name}/"
    spec.summary      = 'A build system that doesn\'t suck'
    spec.files        = FileList['lib/**/*', 'README', 'CHANGELOG', 'LICENSE', 'NOTICE', 'DISCLAIMER',
                                 'Rakefile', 'spec/**/*', 'doc/**/*'].to_ary
    spec.require_path = 'lib'
    spec.has_rdoc     = true
    spec.extra_rdoc_files = ['README', 'CHANGELOG', 'LICENSE', 'NOTICE', 'DISCLAIMER']
    spec.rdoc_options << '--title' << "Buildr -- #{spec.summary}" <<
                         '--main' << 'README' << '--line-numbers' << '--inline-source' << '-p' <<
                         '--webcvs' << 'http://svn.apache.org/repos/asf/incubator/buildr/trunk/'
    spec.rubyforge_project = 'buildr'

    spec.bindir = 'bin'                               # Use these for applications.
    spec.executables = ['buildr']

    # Tested against these dependencies.
    spec.add_dependency 'rake',                 '~> 0.8'
    spec.add_dependency 'facets',               '~> 2.2'
    spec.add_dependency 'builder',              '~> 2.1'
    spec.add_dependency 'net-ssh',              '~> 1.1'
    spec.add_dependency 'net-sftp',             '~> 1.1'
    spec.add_dependency 'rubyzip',              '~> 0.9'
    spec.add_dependency 'highline',             '~> 1.4'
    spec.add_dependency 'Antwrap',              '~> 0.7'
    spec.add_dependency 'rspec',                '~> 1.1'
    spec.add_dependency 'xml-simple',           '~> 1.0'
    spec.add_dependency 'archive-tar-minitar',  '~> 0.5'
    
    spec.platform = platform
    spec.add_dependency 'rjb', '~> 1.1' unless platform == 'java'
  end
end


# Packaging and local installation.
#
ruby_spec = specify(Gem::Platform::RUBY)
jruby_spec = specify('java')
ruby_package = Rake::GemPackageTask.new(ruby_spec) do |pkg|
  pkg.need_tar = true
  pkg.need_zip = true
end
jruby_package = Rake::GemPackageTask.new(jruby_spec) do |pkg|
  pkg.need_tar = false
  pkg.need_zip = false
end

desc 'Install the package locally'
task :install=>:package do |task|
  if RUBY_PLATFORM =~ /java/ 
    cmd = %w(jruby -S gem install)
    pkg = jruby_package
  else 
    cmd = %w(gem install)
    pkg = ruby_package
  end
  cmd << File.expand_path(pkg.gem_file, pkg.package_dir)
  system *cmd
end

desc 'Uninstall previously installed packaged'
task :uninstall do |task|
  if RUBY_PLATFORM =~ /java/ 
    cmd = %w(jruby -S gem uninstall)
    pkg = jruby_package
  else 
    cmd = %w(gem uninstall)
    pkg = ruby_package
  end
  cmd << File.expand_path(pkg.gem_file, pkg.package_dir)
  system *cmd
end


# Testing is everything.
#
desc 'Run all specs'
Spec::Rake::SpecTask.new('spec') do |task|
  task.spec_files = FileList['spec/**/*_spec.rb']
  task.spec_opts << '--options' << 'spec/spec.opts' << '--format' << 'failing_examples:failing'
end

desc 'Run all failing examples'
Spec::Rake::SpecTask.new('failing') do |task|
  task.spec_files = FileList['spec/**/*_spec.rb']
  task.spec_opts << '--options' << 'spec/spec.opts' << '--format' << 'failing_examples:failing' << '--example' << 'failing'
end

desc 'Run all specs and generate reports in html directory'
Spec::Rake::SpecTask.new('spec:report') do |task|
  mkpath 'html'
  task.spec_files = FileList['spec/**/*_spec.rb']
  task.spec_opts << '--format' << 'html:html/report.html' << '--backtrace'
  task.rcov = true
  task.rcov_dir = 'html/coverage'
  task.rcov_opts = ['--exclude', 'spec,bin']
end

task 'spec:jruby' do
  system 'jruby -S rake spec'
end


# Documentation.
#
desc 'Generate RDoc documentation'
rdoc = Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'html/rdoc'
  rdoc.title    = ruby_spec.name
  rdoc.options  = ruby_spec.rdoc_options + ['--promiscuous']
  rdoc.rdoc_files.include('lib/**/*.rb')
  rdoc.rdoc_files.include ruby_spec.extra_rdoc_files
  begin
    gem 'allison'
    rdoc.template = File.expand_path('lib/allison.rb', Gem.loaded_specs['allison'].full_gem_path)
  rescue Exception 
  end
end

desc 'Generate all documentation merged into the html directory'
task 'docs'=>[rdoc.name]

begin
  require 'docter'
  require 'docter/server'
  require 'docter/ultraviolet'

  web_docs = {
    :collection => Docter.collection('Buildr').using('doc/web.toc.yaml').
      include('doc/pages', 'LICENSE', 'CHANGELOG'),
    :template   => Docter.template('doc/web.haml').
      include('doc/css', 'doc/images', 'doc/scripts', 'html/report.html', 'html/coverage', 'html/rdoc')
  }
  print_docs = {
    :collection => Docter.collection('Buildr').using('doc/print.toc.yaml').
      include('doc/pages', 'LICENSE'),
    :template   => Docter.template('doc/print.haml').include('doc/css', 'doc/images')
  }

  Docter.filter_for(:footnote) do |html|
    html.gsub(/<p id="fn(\d+)">(.*?)<\/p>/, %{<p id="fn\\1" class="footnote">\\2</p>})
  end

  desc 'Generate HTML documentation'
  html = Docter::Rake.generate('html', web_docs[:collection], web_docs[:template])
  desc 'Run Docter server'
  Docter::Rake.serve :docter, web_docs[:collection], web_docs[:template], :port=>3000
  task('docs').enhance [html]
  task('clobber') { rm_rf html.to_s }

  if `which prince` =~ /prince/ 
    desc 'Produce PDF'
    print = Docter::Rake.generate('print', print_docs[:collection], print_docs[:template], :one_page)
    pdf = file('html/buildr.pdf'=>print) do |task|
      mkpath 'html'
      sh *%W{prince #{print}/index.html -o #{task.name} --media=print} do |ok, res|
        fail 'Failed to create PDF, see errors above' unless ok
      end
    end
    task('pdf'=>pdf) { |task| `open #{File.expand_path(pdf.to_s)}` }
    task('docs').enhance [pdf]
    task('clobber') { rm_rf print.to_s }
  end

rescue LoadError
  puts "To generate the site documentation and PDF, gem install docter ultraviolet"
end


# Commit to SVN, upload and do the release cycle.
#
namespace :svn do
  task :clean? do |task|
    status = `svn status`.reject { |line| line =~ /\s(pkg|html)$/ }
    fail "Cannot release unless all local changes are in SVN:\n#{status}" unless status.empty?
  end
  
  task :tag do |task|
    cur_url = `svn info`.scan(/URL: (.*)/)[0][0]
    new_url = cur_url.sub(/(trunk$)|(branches\/\w*)$/, "tags/#{ruby_spec.version.to_s}")
    system 'svn', 'copy', cur_url, new_url, '-m', "Release #{ruby_spec.version.to_s}"
  end
end

namespace :upload do
  task :docs=>'rake:docs' do |task|
    sh %{rsync -r --del --progress html/*  people.apache.org:/www/incubator.apache.org/#{ruby_spec.rubyforge_project.downcase}/}
  end

  task :packages=>['rake:docs', 'rake:package'] do |task|
    require 'rubyforge'

    # Read the changes for this release.
    pattern = /(^(\d+\.\d+(?:\.\d+)?)\s+\(\d{4}-\d{2}-\d{2}\)\s*((:?^[^\n]+\n)*))/
    changelog = File.read(__FILE__.pathmap('%d/CHANGELOG'))
    changes = changelog.scan(pattern).inject({}) { |hash, set| hash[set[1]] = set[2] ; hash }
    current = changes[ruby_spec.version.to_s]
    if !current && ruby_spec.version.to_s =~ /\.0$/
      current = changes[ruby_spec.version.to_s.split('.')[0..-2].join('.')] 
    end
    fail "No changeset found for version #{ruby_spec.version}" unless current

    puts "Uploading #{ruby_spec.name} #{ruby_spec.version}"
    files = Dir.glob('pkg/*.{gem,tgz,zip}')
    rubyforge = RubyForge.new
    rubyforge.login    
    File.open('.changes', 'w'){|f| f.write(current)}
    rubyforge.userconfig.merge!('release_changes' => '.changes',  'preformatted' => true)
    rubyforge.add_release ruby_spec.rubyforge_project.downcase, ruby_spec.name.downcase, ruby_spec.version, *files
    rm '.changes'
    puts "Release #{ruby_spec.version} uploaded"
  end
end

namespace :release do

  # TODO:  Check that we're using allison.
  # TODO:  Check that we can generate PDFs.

  task :ready? do
    require 'highline'
    require 'highline/import'

    puts "This version: #{ruby_spec.version}"
    puts
    puts "Top 4 lines form CHANGELOG:'
    puts File.readlines('CHANGELOG')[0..3].map { |l| "  #{l}" }
    puts
    ask('Top-entry in CHANGELOG file includes today\'s date?') =~ /yes/i or
      fail 'Please update CHANGELOG to include the right date'
  end

  task :post do
    next_version = ruby_spec.version.to_ints.zip([0, 0, 1]).map { |a| a.inject(0) { |t,i| t + i } }.join('.')
    puts "Updating lib/buildr.rb to next version number: #{next_version}"
    buildr_rb = File.read(__FILE__.pathmap('%d/lib/buildr.rb')).
      sub(/(VERSION\s*=\s*)(['"])(.*)\2/) { |line| "#{$1}#{$2}#{next_version}#{$2}" } 
    File.open(__FILE__.pathmap('%d/lib/buildr.rb'), 'w') { |file| file.write buildr_rb }
    puts 'Adding entry to CHANGELOG'
    changelog = File.read(__FILE__.pathmap('%d/CHANGELOG'))
    File.open(__FILE__.pathmap('%d/CHANGELOG'), 'w') { |file| file.write "#{next_version} (Pending)\n\n#{changelog}" }
  end

  task :meat=>['clobber', 'svn:clean?', 'spec:jruby', 'spec:report', 'upload:packages', 'upload:docs', 'svn:tag']
end

desc 'Upload release to RubyForge including docs, tag SVN'
task :release=>[ 'release:ready?', 'release:meat', 'release:post' ]


# Handles Java libraries that are part of Buildr.
#
task 'compile' do
  $LOAD_PATH.unshift File.expand_path('lib')
  require 'buildr'
  require 'buildr/jetty'

  # RJB, JUnit and friends.
  Dir.chdir 'lib/java' do
    `javac -source 1.4 -target 1.4 -Xlint:all org/apache/buildr/*.java`
  end

  # Jetty server.
  cp = artifacts(Buildr::Jetty::REQUIRES).each { |task| task.invoke }.map(&:name).join(File::PATH_SEPARATOR)
  Dir.chdir 'lib/buildr' do
    `javac -source 1.4 -target 1.4 -Xlint:all -cp #{cp} org/apache/buildr/*.java`
  end
end


# Apache release:
# - Create MD5/SHA1/PGP signatures
# - Upload to people.apache.org:/www/www.apache.org/dist/incubator/buildr
