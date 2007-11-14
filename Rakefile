require "rubygems"
Gem::manage_gems
require "rake/gempackagetask"
require "spec/rake/spectask"


# Gem specification comes first, other tasks rely on it.
def specify(platform)
  Gem::Specification.new do |spec|
    spec.name         = "buildr"
    spec.version      = File.read(__FILE__.pathmap("%d/lib/buildr.rb")).scan(/VERSION\s*=\s*(['"])(.*)\1/)[0][1]
    spec.author       = "Apache Buildr"
    spec.email        = "buildr-user@incubator.apache.org"
    spec.homepage     = "http://incubator.apache.org/#{spec.name}/"
    spec.summary      = "A build system that doesn't suck"
    spec.files        = FileList["lib/**/*", "CHANGELOG", "README", "LICENSE", "NOTICE", "DISCLAIMER", "Rakefile"].collect
    spec.require_path = "lib"
    spec.autorequire  = "buildr.rb"
    spec.has_rdoc     = true
    spec.extra_rdoc_files = ["README", "CHANGELOG", "LICENSE"]
    spec.rdoc_options << "--title" << "Buildr -- #{spec.summary}" <<
                         "--main" << "README" << "--line-numbers" << "-inline-source"
    spec.rubyforge_project = "buildr"

    spec.bindir = "bin"                               # Use these for applications.
    spec.executables = ["buildr"]

    # Tested against these dependencies.
    spec.add_dependency "rake",                 "= 0.7.3"
    spec.add_dependency "facets",               "= 1.8.54"
    spec.add_dependency "builder",              "= 2.1.2"
    spec.add_dependency "net-ssh",              "= 1.1.2"
    spec.add_dependency "net-sftp",             "= 1.1.0"
    spec.add_dependency "rubyzip",              "= 0.9.1"
    spec.add_dependency "highline",             "= 1.4.0"
    spec.add_dependency "Antwrap",              "= 0.6.0"
    spec.add_dependency "rspec",                "= 1.0.8"
    spec.add_dependency "xml-simple",           "= 1.0.11"
    spec.add_dependency "archive-tar-minitar",  "= 0.5.1"
    
    spec.platform = platform

    yield spec if block_given?
  end
end

spec = specify(Gem::Platform::RUBY) { |spec| spec.add_dependency "rjb", ">= 1.0.11" }
jruby_spec = specify('java')
package = Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = true
  pkg.need_zip = true
end
jruby_package = Rake::GemPackageTask.new(jruby_spec)

desc "Install the package locally"
task :install=>:package do |task|
  install = RUBY_PLATFORM == 'java' ? jruby_package : package
  system 'gem', 'install', File.expand_path(install.gem_file, install.package_dir)
end

desc "Uninstall previously installed packaged"
task :uninstall do |task|
  install = RUBY_PLATFORM == 'java' ? jruby_package : package
  system "gem", "uninstall", install.name, "-v", install.version.to_s
end


# Testing is everything.
desc "Run test cases"
Spec::Rake::SpecTask.new(:test) do |task|
  task.spec_files = FileList["test/**/*.rb"]
  task.spec_opts = [ "--format", "specdoc", "--color", "--diff" ]
end

desc "Run test cases with rcov"
Spec::Rake::SpecTask.new(:rcov) do |task|
  task.spec_files = FileList["test/**/*.rb"]
  task.spec_opts = [ "--format", "specdoc", "--color", "--diff" ]
  task.rcov = true
end


# Documentation.
begin
  require "rake/rdoctask"
  require "docter"
  require "docter/server"
  require "docter/ultraviolet"

  desc "Generate RDoc documentation"
  rdoc = Rake::RDocTask.new(:rdoc) do |rdoc|
    rdoc.rdoc_dir = "html/rdoc"
    rdoc.title    = spec.name
    rdoc.options  = spec.rdoc_options
    rdoc.rdoc_files.include("lib/**/*.rb")
    rdoc.rdoc_files.include spec.extra_rdoc_files
  end

  web_collection = Docter.collection.using("doc/web.toc.textile").include("doc/pages", "CHANGELOG")
  web_template = Docter.template("doc/web.haml").include("doc/css", "doc/images")
  print_collection = Docter.collection.using("doc/print.toc.textile").include("doc/pages")
  print_template = Docter.template("doc/print.haml").include("doc/css", "doc/images")

  Docter.filter_for(:footnote) do |html|
    html.gsub(/<p id="fn(\d+)">(.*?)<\/p>/, %{<p id="fn\\1" class="footnote">\\2</p>})
  end

  desc "Produce PDF"
  print = Docter::Rake.generate("print", print_collection, print_template, :one_page)
  pdf_file = file("html/buildr.pdf"=>print) do |task|
    mkpath "html"
    sh *%W{prince #{print}/index.html -o #{task.name}} do |ok, res|
      fail "Failed to create PDF, see errors above" unless ok
    end
  end
  task("pdf"=>pdf_file) { |task| `kpdf #{File.expand_path(pdf_file.to_s)}` }

  desc "Generate HTML documentation"
  html = Docter::Rake.generate("html", web_collection, web_template)
  desc "Run Docter server"
  Docter::Rake.serve :docter, web_collection, web_template, :port=>3000

  desc "Generate all documentation merged into the html directory"
  task "docs"=>[html, rdoc.name, pdf_file]
  task("clobber") { rm_rf [html, print].map(&:to_s) }

rescue LoadError=>error
  puts error
  puts "To create the Buildr documentation you need to:"
  puts "  gem install docter"
  puts "  gem install ultraviolet"
end


# Commit to SVN, upload and do the release cycle.
namespace :svn do
  task :clean? do |task|
    status = `svn status`.reject { |line| line =~ /\s(pkg|html)$/ }
    fail "Cannot release unless all local changes are in SVN:\n#{status}" unless status.empty?
  end
  
  task :tag do |task|
    cur_url = `svn info`.scan(/URL: (.*)/)[0][0]
    new_url = cur_url.sub(/trunk$/, "tags/#{spec.version.to_s}")
    system "svn", "remove", new_url, "-m", "Removing old copy" rescue nil
    system "svn", "copy", cur_url, new_url, "-m", "Release #{spec.version.to_s}"
  end
end

namespace :upload do

  task :docs=>"rake:docs" do |task|
    sh "rsync -r --del --progress html/*  people.apache.org:/www/incubator.apache.org/#{spec.rubyforge_project.downcase}/"
  end

  task :packages=>["rake:docs", "rake:package"] do |task|
    require 'rubyforge'

    # Read the changes for this release.
    pattern = /(^(\d+\.\d+(?:\.\d+)?)\s+\(\d+\/\d+\/\d+\)\s*((:?^[^\n]+\n)*))/
    changelog = File.read(__FILE__.pathmap("%d/CHANGELOG"))
    changes = changelog.scan(pattern).inject({}) { |hash, set| hash[set[1]] = set[2] ; hash }
    current = changes[spec.version.to_s]
    if !current && spec.version.to_s =~ /\.0$/
      current = changes[spec.version.to_s.split(".")[0..-2].join(".")] 
    end
    fail "No changeset found for version #{spec.version}" unless current

    puts "Uploading #{spec.name} #{spec.version}"
    files = Dir.glob('pkg/*.{gem,tgz,zip}')
    rubyforge = RubyForge.new
    rubyforge.login    
    File.open(".changes", 'w'){|f| f.write(current)}
    rubyforge.userconfig.merge!("release_changes" => ".changes",  "preformatted" => true)
    rubyforge.add_release spec.rubyforge_project.downcase, spec.name.downcase, spec.version, *files
    rm ".changes"
    puts "Release #{spec.version} uploaded"
  end
end

namespace :release do
  task :ready? do
    require 'highline'
    require 'highline/import'

    puts "This version: #{spec.version}"
    puts
    puts "Top 4 lines form CHANGELOG:"
    puts File.readlines("CHANGELOG")[0..3].map { |l| "  #{l}" }
    puts
    ask("Top-entry in CHANGELOG file includes today's date?") =~ /yes/i or
      fail "Please update CHANGELOG to include the right date"
  end

  task :post do
    # Practical example of functional read but not comprehend code:
    next_version = spec.version.to_ints.zip([0, 0, 1]).map { |a| a.inject(0) { |t,i| t + i } }.join(".")
    puts "Updating lib/buildr.rb to next version number: #{next_version}"
    buildr_rb = File.read(__FILE__.pathmap("%d/lib/buildr.rb")).
      sub(/(VERSION\s*=\s*)(['"])(.*)\2/) { |line| "#{$1}#{$2}#{next_version}#{$2}" } 
    File.open(__FILE__.pathmap("%d/lib/buildr.rb"), "w") { |file| file.write buildr_rb }
    puts "Adding entry to CHANGELOG"
    changelog = File.read(__FILE__.pathmap("%d/CHANGELOG"))
    File.open(__FILE__.pathmap("%d/CHANGELOG"), "w") { |file| file.write "#{next_version} (Pending)\n\n#{changelog}" }
  end

  task :meat=>["clobber", "svn:clean?", "test", "upload:packages", "upload:docs", "svn:tag"]
end

desc "Upload release to RubyForge including docs, tag SVN"
task :release=>[ "release:ready?", "release:meat", "release:post" ]


# Misc, may not survive so don't rely on these.
task :report do |task|
  puts "#{spec.name} #{spec.version}"
  puts spec.summary
  sources = (spec.files + FileList["test/**/*.rb"]).reject { |f| File.directory?(f) }
  sources.inject({}) do |lists, file|
    File.readlines(file).each_with_index do |line, i|
      if line =~ /(TODO|FIXME|NOTE):\s*(.*)/
        list = lists[$1] ||= []
        list << sprintf("%s (%d): %s", file, i, $2)
      end
    end
    lists
  end.each_pair do |type, list|
    unless list.empty?
      puts
      puts "#{type}:"
      list.each { |line| puts line }
    end
  end
end

namespace :setup do
  task :jetty do
    cp = ["jetty-6.1.1.jar", "jetty-util-6.1.1.jar", "servlet-api-2.5-6.1.1"].
      map { |jar| `locate #{jar}`.split.first }.join(File::PATH_SEPARATOR)
    Dir.chdir "lib/buildr/jetty" do
      `javac -cp #{cp} JettyWrapper.java`
    end
  end
end
