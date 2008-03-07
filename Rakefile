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


ruby_spec = specify(Gem::Platform::RUBY)
ruby_package = Rake::GemPackageTask.new(ruby_spec) { |pkg| pkg.need_tar = pkg.need_zip = true }

jruby_spec = specify('java')
jruby_package = Rake::GemPackageTask.new(jruby_spec) { |pkg| pkg.need_tar = pkg.need_zip = false }

begin
  require 'rubygems/dependency_installer'
  def install_gem(gem, options = {})
    say "Installing #{gem}..."
    installer = Gem::DependencyInstaller.new(gem, options.delete(:version), options)
    installer.install
    installer.installed_gems.each do |spec|
      Gem::DocManager.new(spec).generate_ri unless options[:ri] == false
      Gem::DocManager.new(spec).generate_rdoc unless options[:rdoc] == false
    end
  end
rescue LoadError # < rubygems 1.0.1
  require 'rubygems/remote_installer'
  def install_gem(gem, options = {})
    say "Installing #{gem}..."
    Gem::RemoteInstaller.new.install(gem, options.delete(:version))
    say 'OK'
  end
end


# Setup environment for running this Rakefile (RSpec, Docter, etc).
desc "If you're building from sources, run this task one to setup the necessary dependencies."
task 'setup' do
  # Install all Buildr and documentation dependencies.
  gems = Gem::SourceIndex.from_installed_gems
  dependencies = specify(RUBY_PLATFORM).dependencies
  dependencies << Gem::Dependency.new('docter', '~>1.1')
  dependencies << Gem::Dependency.new('ultraviolet', '~>0.10') unless RUBY_PLATFORM =~ /java/
  dependencies << Gem::Dependency.new('rcov', '~>0.8') unless RUBY_PLATFORM =~ /java/ 
  dependencies.select { |dep| gems.search(dep.name, dep.version_requirements).empty? }.
    each { |dep| install_gem dep.name, :version=>dep.version_requirements }
end

# Packaging and local installation.
#
desc 'Clean up all temporary directories used for running tests, creating documentation, packaging, etc.'
task('clobber') { rm_rf 'pkg' }

desc 'Install the package locally'
task 'install'=>['clobber', 'package'] do |task|
  pkg = RUBY_PLATFORM =~ /java/ ? jruby_package : ruby_package
  # install_gem File.expand_path(pkg.gem_file, pkg.package_dir)
  ruby 'install', File.expand_path(pkg.gem_file, pkg.package_dir), :command=>'gem', :sudo=>true
end

def ruby(*args)
  options = Hash === args.last ? args.pop : {}
  #options[:verbose] ||= false
  cmd = []
  cmd << 'sudo' if options.delete(:sudo) && !Gem.win_platform? && RUBY_PLATFORM !~ /java/
  cmd << Config::CONFIG['ruby_install_name']
  cmd << '-S' << options.delete(:command) if options[:command]
  sh *cmd.push(*args.flatten).push(options)
end

desc 'Uninstall previously installed packaged'
task 'uninstall' do |task|
  say "Uninstalling #{ruby_spec.name} ... "
  ruby 'install', name_or_path.to_s, :command=>'gem', :sudo=>true
=begin
  begin
    require 'rubygems/uninstaller'
  rescue LoadError # < rubygems 1.0.1
    require 'rubygems/installer'
  end
  Gem::Uninstaller.new(ruby_spec.name, :executables=>true, :ignore=>true ).uninstall
=end
  say 'Done'
end


# Testing is everything.
#
task('clobber') { rm 'failing' rescue nil }

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


namespace 'spec' do

  directory('reports')
  Rake::Task['rake:clobber'].enhance { rm_rf 'reports' }

  desc 'Run all specs and generate specification and test coverage reports in html directory'
  Spec::Rake::SpecTask.new('full'=>'reports') do |task|
    task.spec_files = FileList['spec/**/*_spec.rb']
    task.spec_opts << '--format' << 'html:reports/specs.html' << '--backtrace'
    task.rcov = true
    task.rcov_dir = 'reports/coverage'
    task.rcov_opts = ['--exclude', 'spec,bin']
  end

  desc 'Run all specs specifically with Ruby'
  task('ruby') { system 'ruby -S rake spec' }

  desc 'Run all specs specifically with JRuby'
  task('jruby') { system 'jruby -S rake spec' }

end


# Documentation.
#
desc 'Generate RDoc documentation'
rdoc = Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
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
      include('doc/css', 'doc/images', 'doc/scripts', 'reports/specs.html', 'reports/coverage', 'rdoc')
  }
  print_docs = {
    :collection => Docter.collection('Buildr').using('doc/print.toc.yaml').
      include('doc/pages', 'LICENSE'),
    :template   => Docter.template('doc/print.haml').include('doc/css', 'doc/images')
  }

  #Docter.filter_for(:footnote) do |html|
  #  html.gsub(/<p id="fn(\d+)">(.*?)<\/p>/, %{<p id="fn\\1" class="footnote">\\2</p>})
  #end

  desc 'Generate HTML documentation'
  html = Docter::Rake.generate('html', web_docs[:collection], web_docs[:template])
  html.enhance ['spec:full']

  desc 'Run Docter server'
  Docter::Rake.serve 'docter', web_docs[:collection], web_docs[:template], :port=>3000
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
  puts "To generate site documentation, run rake setup first"
end


namespace 'release' do
 
  begin
    require 'highline'
    require 'highline/import'
    Kernel.def_delegators :$terminal, :color
  rescue LoadError 
    puts 'HighLine required, please run rake setup first'
  end

  # This task does all prerequisites checks before starting the release, for example,
  # that we have Groovy and Scala to run all the test cases, or that we have Allison
  # and PrinceXML to generate the full documentation.
  task 'check'=>'setup'
  # This task does all the preparation work before making a release and also checks
  # that we generate all the right material, for example, that we compiled Java sources,
  # created the PDF, have coverage report.
  task 'prepare'=>['clobber', 'check']

  # Does CHANGELOG reflects current release?
  task 'check' do
    say 'Checking that CHANGELOG indicates most recent version and today\'s date ... '
    expecting = "#{ruby_spec.version} (#{Time.now.strftime('%Y-%m-%d')})"
    header = File.readlines('CHANGELOG').first
    fail "Expecting CHANGELOG to start with #{expecting}, but found #{header} instead" unless expecting == header
    say 'OK'
  end

  # License requirement.
  task 'check' do
    say 'Checking that files contain the Apache license ... '
    directories = 'lib', 'spec', 'docs', 'bin'
    ignore = 'class', 'opts'
    FileList['lib/**/*', 'spec/**/*', 'bin/**', 'doc/css/*', 'doc/scripts/*'].
      exclude('doc/css/eiffel.css').reject { |file| File.directory?(file) || ignore.include?(file[/[^.]*$/]) }.each do |file|
      comments = File.read(file).scan(/(\/\*(.*?)\*\/)|^#\s+(.*?)$|<!--(.*?)-->/m).
        map { |match| match.reject(&:nil?) }.flatten.join("\n")
      fail "File #{file} missing Apache License, please add it before making a release!" unless
        comments =~ /Licensed to the Apache Software Foundation/ && comments =~ /http:\/\/www.apache.org\/licenses\/LICENSE-2.0/
    end
    say 'OK'
  end

  # No local changes.
  task 'check' do
    status = `svn status`
    fail "Cannot release unless all local changes are in SVN:\n#{status}" unless status.empty?
  end

  # Re-generate Java extensions and to this before running test cases.
  task 'compile' do
    say 'Compiling Java libraries ... '
    cmd = [ RUBY_PLATFORM =~ /java/ ? 'jruby' : 'ruby' ] <<
      '-I' << File.join(File.dirname(__FILE__), 'lib') <<
      File.join(File.dirname(__FILE__), 'bin', 'buildr') <<
      'compile'
    system *cmd
    say 'OK'
  end

  # Tests, specs and coverage reports.
  task 'check' do
    say 'Checking that we have JRuby, Scala and Groovy available ... '
    fail 'Full testing requires JRuby!' if `which jruby`.empty?
    fail 'Full testing requires Scala!' if `which scalac`.empty? || ENV['SCALA_HOME'].to_s.empty?
    fail 'Full testing requires Groovy!' if `which groovyc`.empty?
    say 'OK'
  end
  task 'prepare'=>'compile' do
    say 'Running test suite using JRuby ...'
    task('spec:jruby').invoke
    say 'Running test suite using Ruby ...'
    task('spec:ruby').invoke
    say 'Done'
  end

  # Documentation (derived from above).
  task 'check' do
    say 'Checking that we can use Allison and PrinceXML ... '
    fail 'Release requires the Allison RDoc template, please gem install allison!' unless rdoc.template =~ /allison.rb/
    fail 'Release requires PrinceXML to generate PDF documentation!' if `which prince`.empty?
    say 'OK'
  end
  task 'prepare'=>'spec:full' do
    say 'Generating RDocs and PDF ...'
    task('docs').invoke
    say 'Done'

    say 'Checking that we have PDF, RDoc, specs and coverage report ... '
    fail 'No RDocs if html/rdoc!' unless File.exist?('html/rdoc/files/lib/buildr_rb.html')
    fail 'No PDF generated, you need to install PrinceXML!' unless File.exist?('html/buildr.pdf')
    fail 'No specifications in html directory!' unless File.exist?('html/specs.html') 
    fail 'No coverage reports in html/coverage directory!' unless File.exist?('html/coverage/index.html')
    say 'OK'
  end

  task 'check' do
    require 'rubyforge' rescue fail 'RubyForge required, please gem install rubyforge!'
    fail 'GnuPG required to create signatures!' if `which gpg`.empty?
    gpg_user = ENV['GPG_USER'] or fail 'Please set GPG_USER (--local-user) environment variable so we know which key to use.'
    sh('gpg', '--list-key', gpg_user) { |ok, res| ok or fail "No key matches for GPG_USER=#{gpg_user}" }
  end

 
  # Cut the release: upload Gem to RubyForge before updating site (fail safe).
  task 'cut'=>['upload:rubyforge', 'upload:site']


  namespace 'upload' do
    # Upload site (html directory) to Apache.
    task 'site'=>'rake:docs' do
      say 'Uploading Web site to people.apache.org ... '
      args = Dir.glob('html/*') + ['people.apache.org:/www/incubator.apache.org/' + ruby_spec.rubyforge_project.downcase]
      verbose(false) { sh 'rsync ', '-r', '--del', '--progress', *files }
      say 'Done'
    end

    # Upload Gems to RubyForge.
    task 'rubyforge'=>['rake:docs', 'rake:package'] do
      require 'rubyforge'

      # Read the changes for this release.
      say 'Looking for changes between this release and previous one ... '
      pattern = /(^(\d+\.\d+(?:\.\d+)?)\s+\(\d{4}-\d{2}-\d{2}\)\s*((:?^[^\n]+\n)*))/
      changelog = File.read(__FILE__.pathmap('%d/CHANGELOG'))
      changes = changelog.scan(pattern).inject({}) { |hash, set| hash[set[1]] = set[2] ; hash }
      current = changes[ruby_spec.version.to_s]
      current = changes[ruby_spec.version.to_s.split('.')[0..-2].join('.')] if !current && ruby_spec.version.to_s =~ /\.0$/
      fail "No changeset found for version #{ruby_spec.version}" unless current
      say 'OK'

      say "Uploading #{ruby_spec.version} to RubyForge ... "
      files = Dir.glob('pkg/*.{gem,tgz,zip}')
      rubyforge = RubyForge.new
      rubyforge.login    
      File.open('.changes', 'w'){|f| f.write(current)}
      rubyforge.userconfig.merge!('release_changes' => '.changes',  'preformatted' => true)
      rubyforge.add_release ruby_spec.rubyforge_project.downcase, ruby_spec.name.downcase, ruby_spec.version, *files
      rm '.changes'
      say 'Done'
    end

    task 'apache'=>['rake:package'] do
      require 'md5'
      require 'sha1'

      gpg_user = ENV['GPG_USER'] or fail 'Please set GPG_USER (--local-user) environment variable so we know which key to use.'
      say 'Creating -incubating packages ... '
      rm_rf 'incubating'
      mkpath 'incubating'
      packages = FileList['pkg/*.{gem,zip,tgz}'].map do |package|
        package.pathmap('incubating/%n-incubating%x').tap do |incubating|
          cp package, incubating
        end
      end
      say 'Done'

      say 'Signing -incubating packages ... '
      files = packages.each do |package|
        binary = File.read(package)
        File.open(package + '.md5', 'w') { |file| file.write MD5.hexdigest(binary) << ' ' << package }
        File.open(package + '.sha1', 'w') { |file| file.write SHA1.hexdigest(binary) << ' ' << package }
        sh 'gpg', '--local-user', gpg_user, '--armor', '--output', package + '.asc', '--detach-sig', package, :verbose=>true
        [package, package + '.md5', package + '.sha1', package + '.asc']
      end
      say 'Done'

      say 'Uploading packages to Apache dist ... '
      args = files.flatten << 'KEYS' << 'people.apache.org:/www.apache.org/dist/incubator/buildr/'
      verbose(false) { sh 'rsync', '-progress', *args }
      say 'Done'
    end
    Rake::Task['rake:clobber'].enhance { rm_rf 'incubating' }

  end


  # Tag this release in SVN.
  task 'tag' do
    say "Tagging release as tags/#{ruby_spec.version} ... "
    cur_url = `svn info`.scan(/URL: (.*)/)[0][0]
    new_url = cur_url.sub(/(trunk$)|(branches\/\w*)$/, "tags/#{ruby_spec.version.to_s}")
    sh 'svn', 'copy', cur_url, new_url, '-m', "Release #{ruby_spec.version.to_s}", :verbose=>false
    say "OK"
  end

  # Update lib/buildr.rb to next vesion number, add new entry in CHANGELOG.
  task 'next_version'=>'tag' do
    next_version = ruby_spec.version.to_ints.zip([0, 0, 1]).map { |a| a.inject(0) { |t,i| t + i } }.join('.')
    say "Updating lib/buildr.rb to next version number (#{next_version}) ... "
    buildr_rb = File.read(__FILE__.pathmap('%d/lib/buildr.rb')).
      sub(/(VERSION\s*=\s*)(['"])(.*)\2/) { |line| "#{$1}#{$2}#{next_version}#{$2}" } 
    File.open(__FILE__.pathmap('%d/lib/buildr.rb'), 'w') { |file| file.write buildr_rb }
    say "OK"

    say 'Adding new entry to CHANGELOG ... '
    changelog = File.read(__FILE__.pathmap('%d/CHANGELOG'))
    File.open(__FILE__.pathmap('%d/CHANGELOG'), 'w') { |file| file.write "#{next_version} (Pending)\n\n#{changelog}" }
    say "OK"
  end

  # Wrapup comes after cut, and does things like tagging in SVN, updating Buildr version number, etc.
  task 'wrapup'=>['tag', 'next_version']
end

task 'release'=>['release:prepare', 'release:cut', 'release:wrapup']
