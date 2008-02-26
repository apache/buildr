require 'buildr/jetty'

repositories.remote << "http://www.ibiblio.org/maven2/"

options = :javac, { :source=>'1.4', :target=>'1.4', :debug=>false }
define 'java' do
  compile.from(FileList['lib/java/**/*.java']).into('lib/java').using(*options).with(Buildr::JUnit::REQUIRES)
end
define 'buildr' do
  compile.from(FileList['lib/buildr/**/*.java']).into('lib/buildr').using(*options).with(Buildr::Jetty::REQUIRES)
end
