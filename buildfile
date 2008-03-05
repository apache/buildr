require 'buildr/jetty'

def package_addon(project, *files)
  legal = 'LICENSE', 'DISCLAIMER', 'NOTICE'
  project.package(:gem).include(legal)
  project.package(:gem).path('lib').tap do |lib|
    files.each do |file|
      lib.include(file, :as=>File.basename(file))
    end
  end
  project.package(:gem).spec do |spec|
    spec.author             = 'Apache Buildr'
    spec.email              = 'buildr-user@incubator.apache.org'
    spec.homepage           = "http://incubator.apache.org/buildr"
    spec.rubyforge_project  = 'buildr'
    spec.extra_rdoc_files   = legal
    spec.rdoc_options << '--webcvs' << 'http://svn.apache.org/repos/asf/incubator/buildr/trunk/'
    spec.add_dependency 'buildr', '~> 1.3'
  end
end

define 'buildr' do
  compile.using :source=>'1.4', :target=>'1.4', :debug=>false

  define 'java' do
    require 'java/nailgun'
    compile.using(:javac).from(FileList['lib/java/**/*.java']).into('lib/java').with(Buildr::Nailgun.artifact)
  end

  desc 'ANTLR grammar generation tasks.'
  define 'antlr', :version=>'1.0' do
    package_addon(self, 'lib/buildr/antlr.rb')
  end

  define 'cobertura', :version=>'1.0' do
    package_addon(self, 'lib/buildr/cobertura.rb')
  end

  define 'hibernate', :version=>'1.0' do
    package_addon(self, 'lib/buildr/hibernate.rb')
  end

  define 'javacc', :version=>'1.0' do
    package_addon(self, 'lib/buildr/javacc.rb')
  end

  define 'jdepend', :version=>'1.0' do
    package_addon(self, 'lib/buildr/jdepend.rb')
  end

  desc 'Provides a collection of tasks and methods for using Jetty, specifically as a server for testing your application.'
  define 'jetty', :version=>'1.0' do
    compile.using(:javac).from(FileList['lib/buildr/**/*.java']).into('lib/buildr').with(Buildr::Jetty::REQUIRES)
    package_addon(self, 'lib/buildr/jetty.rb')
    package(:gem).path('lib/org/apache/buildr').include(:from=>'lib/buildr/org/apache/buildr/')
  end

  define 'openjpa', :version=>'1.0' do
    package_addon(self, 'lib/buildr/openjpa.rb')
  end

  define 'xmlbeans', :version=>'1.0' do
    package_addon(self, 'lib/buildr/xmlbeans.rb')
  end
end
