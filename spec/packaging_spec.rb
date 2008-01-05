require File.join(File.dirname(__FILE__), 'spec_helpers')


describe Project, "#group" do
  it "should default to project name" do
    desc "My Project"
    define "foo"
    project("foo").group.should eql("foo")
  end

  it "should be settable" do
    define "foo", :group=>"bar"
    project("foo").group.should eql("bar")
  end

  it "should inherit from parent project" do
    define("foo", :group=>"groupie") { define "bar" }
    project("foo:bar").group.should eql("groupie")
  end
end

describe Project, "#version" do
  it "should default to nil" do
    define "foo"
    project("foo").version.should be_nil
  end

  it "should be settable" do
    define "foo", :version=>"2.1"
    project("foo").version.should eql("2.1")
  end

  it "should inherit from parent project" do
    define("foo", :version=>"2.1") { define "bar" }
    project("foo:bar").version.should eql("2.1")
  end

end


describe Project, "#id" do
  it "should be same as project name" do
    define "foo"
    project("foo").id.should eql("foo")
  end

  it "should replace colons with dashes" do
    define("foo", :version=>"2.1") { define "bar" }
    project("foo:bar").id.should eql("foo-bar")
  end

  it "should not be settable" do
    lambda { define "foo", :id=>"bar" }.should raise_error(NoMethodError)
  end
end


describe Project, "#manifest" do
  it "should include user name" do
    ENV["USER"] = "MysteriousJoe"
    define "foo"
    project("foo").manifest["Build-By"].should eql("MysteriousJoe")
  end

  it "should include JDK version" do
    Java.stub!(:version).and_return "1.6_6"
    define "foo"
    project("foo").manifest["Build-Jdk"].should eql("1.6_6")
  end

  it "should include project comment" do
    desc "My Project"
    define "foo"
    project("foo").manifest["Implementation-Title"].should eql("My Project")
  end

  it "should include project name if no comment" do
    define "foo"
    project("foo").manifest["Implementation-Title"].should eql("foo")
  end

  it "should include project version" do
    define "foo", :version=>"2.1"
    project("foo").manifest["Implementation-Version"].should eql("2.1")
  end

  it "should not include project version unless specified" do
    define "foo"
    project("foo").manifest["Implementation-Version"].should be_nil
  end

  it "should inherit from parent project" do
    define("foo", :version=>"2.1") { define "bar" }
    project("foo:bar").manifest["Implementation-Version"].should eql("2.1")
  end

end


describe Project, "#meta_inf" do
  it "should by an array" do
    define "foo"
    project("foo").meta_inf.should be_kind_of(Array)
  end

  it "should include LICENSE file if found" do
    write "LICENSE"
    define "foo"
    project("foo").meta_inf.first.should point_to_path("LICENSE")
  end

  it "should be empty unless LICENSE exists" do
    define "foo"
    project("foo").meta_inf.should be_empty
  end

  it "should inherit from parent project" do
    write "LICENSE"
    define("foo") { define "bar" }
    project("foo:bar").meta_inf.first.should point_to_path("LICENSE")
  end

  it "should expect LICENSE file parent project" do
    write "bar/LICENSE"
    define("foo") { define "bar" }
    project("foo:bar").meta_inf.should be_empty
  end
end


describe Project, "#package" do
  it "should default to id from project" do
    pkgs = []
    define("foo", :version=>"1.0") do
      pkgs << package(:jar)
      define "bar" do
        pkgs << package(:jar)
      end
    end
    pkgs.map(&:id).should eql(["foo", "foo-bar"])
  end

  it "should take id from option if specified" do
    pkg = nil
    define("foo", :version=>"1.0") { pkg = package(:jar, :id=>"bar") }
    pkg.id.should eql("bar")
  end

  it "should default to group from project" do
    pkg = nil
    define("foo", :version=>"1.0") { pkg = package(:jar) }
    pkg.group.should eql("foo")
  end

  it "should take group from option if specified" do
    pkg = nil
    define("foo", :version=>"1.0") { pkg = package(:jar, :group=>"bar") }
    pkg.group.should eql("bar")
  end

  it "should default to version from project" do
    pkg = nil
    define("foo", :version=>"1.0") { pkg = package(:jar) }
    pkg.version.should eql("1.0")
  end

  it "should take version from option if specified" do
    pkg = nil
    define("foo", :version=>"1.0") { pkg = package(:jar, :version=>"2.0") }
    pkg.version.should eql("2.0")
  end

  it "should accept package type as first argument" do
    pkg = nil
    define("foo", :version=>"1.0") { pkg = package(:war) }
    pkg.type.should eql(:war)
  end

  it "should assume :zip package type unless specified" do
    define("foo", :version=>"1.0")
    project('foo').package.type.should eql(:zip)
  end

  it 'should infer packaging type from compiler' do
    define("foo", :version=>"1.0") { compile.using(:javac) }
    project('foo').package.type.should eql(:jar)
  end

  it "should default to no classifier" do
    pkg = nil
    define("foo", :version=>"1.0") { pkg = package(:jar) }
    pkg.classifier.should be_nil
  end

  it "should accept classifier from option" do
    pkg = nil
    define("foo", :version=>"1.0") { pkg = package(:jar, :classifier=>"srcs") }
    pkg.classifier.should eql("srcs")
  end

  it "should fail if no packager" do
    lambda { define("foo") { package(:weirdo) } }.should raise_error(RuntimeError, /Don't know how to create a package/)
  end

  it "should return a file task" do
    define("foo", :version=>"1.0") { package(:jar) }
    project("foo").package(:jar).should be_kind_of(Rake::FileTask) 
  end

  it "should return a task that acts as artifact" do
    define("foo", :version=>"1.0") { package(:jar) }
    project("foo").package(:jar).should respond_to(:to_spec)
    project("foo").package(:jar).to_spec.should eql("foo:foo:jar:1.0")
  end

  it "should create different tasks for each spec" do
    define("foo", :version=>"1.0") do
      package(:jar)
      package(:war)
      package(:jar, :id=>"bar")
      package(:jar, :classifier=>"srcs")
    end
    project("foo").packages.size.should be(4)
  end

  it "should return the same task for the same spec" do
    define("foo", :version=>"1.0") do
      package(:war)
      package(:war)
      package(:jar, :id=>"bar")
      package(:jar, :id=>"bar")
    end
    project("foo").packages.size.should be(2)
    project("foo").packages.first.type.should eql(:war)
    project("foo").packages.last.id.should eql("bar")
  end

  it "should register task as artifact" do
    define("foo", :version=>"1.0") do
      package(:jar, :id=>"bar")
      package(:war)
    end
    project("foo").packages.should eql(artifacts("foo:bar:jar:1.0", "foo:foo:war:1.0"))
  end

  it "should create in target class" do
    define("foo", :version=>"1.0") do
      package(:war)
      package(:jar, :id=>"bar")
      package(:zip, :classifier=>"srcs")
    end
    project("foo").packages[0].should point_to_path("target/foo-1.0.war")
    project("foo").packages[1].should point_to_path("target/bar-1.0.jar")
    project("foo").packages[2].should point_to_path("target/foo-1.0-srcs.zip")
  end

  it "should create prerequisite for package task" do
    define("foo", :version=>"1.0") do
      package(:war)
      package(:jar, :id=>"bar")
      package(:jar, :classifier=>"srcs")
    end
    project("foo").packages.map(&:to_s).
      each { |package| project("foo").task("package").prerequisites.map(&:to_s).should include(package) }
  end

  it "should create task requiring a build" do
    define("foo", :version=>"1.0") do
      package(:war)
      package(:jar, :id=>"bar")
      package(:jar, :classifier=>"srcs")
    end
    project("foo").packages.each { |pkg| pkg.prerequisites.should include(project("foo").build) }
  end

  it "should create a POM artifact in local repository" do
    define("foo", :version=>"1.0") { package(:jar, :classifier=>"srcs") }
    Artifact.lookup("foo:foo:pom:1.0").should_not be_nil
    Artifact.lookup("foo:foo:pom:1.0").should be(project("foo").packages.first.pom)
    repositories.locate("foo:foo:pom:1.0").should eql(project("foo").packages.first.pom.to_s)
  end

  it "should create POM artifact that creates its own POM" do
    define("foo", :group=>"bar", :version=>"1.0") { package(:jar, :classifier=>"srcs") }
    project("foo").packages.first.pom.invoke
    read(project("foo").packages.first.pom.to_s).should eql(<<-POM
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>bar</groupId>
  <artifactId>foo</artifactId>
  <version>1.0</version>
</project>
POM
    )
  end

  it "should not require downloading artifact or POM" do
    task("artifacts").instance_eval { @actions.clear }
    define("foo", :group=>"bar", :version=>"1.0") { package(:jar, :classifier=>"srcs") }
    task("artifacts").invoke
  end

end


describe Rake::Task, " package" do
  it "should be local task" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    in_original_dir project("foo:bar").base_dir do
      task("package").invoke
      project("foo").package.should_not exist
      project("foo:bar").package.should exist
    end
  end

  it "should be recursive task" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    task("package").invoke
    project("foo").package.should exist
    project("foo:bar").package.should exist
  end

  it "should create package in target directory" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    task("package").invoke
    FileList["**/target/*.zip"].map.sort.should == ["bar/target/foo-bar-1.0.zip", "target/foo-1.0.zip"]
  end
end


describe Rake::Task, " install" do
  it "should be local task" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    in_original_dir project("foo:bar").base_dir do
      task("install").invoke
      artifacts("foo:foo:zip:1.0", "foo:foo:pom:1.0").each { |t| t.should_not exist }
      artifacts("foo:foo-bar:zip:1.0", "foo:foo-bar:pom:1.0").each { |t| t.should exist }
    end
  end

  it "should be recursive task" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    task("install").invoke
    artifacts("foo:foo:zip:1.0", "foo:foo:pom:1.0", "foo:foo-bar:zip:1.0", "foo:foo-bar:pom:1.0").each { |t| t.should exist }
  end

  it "should create package in local repository" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    task("install").invoke
    FileList[repositories.local + "/**/*"].reject { |f| File.directory?(f) }.sort.should == [
      File.expand_path("foo/foo/1.0/foo-1.0.zip", repositories.local),
      File.expand_path("foo/foo/1.0/foo-1.0.pom", repositories.local),
      File.expand_path("foo/foo-bar/1.0/foo-bar-1.0.zip", repositories.local),
      File.expand_path("foo/foo-bar/1.0/foo-bar-1.0.pom", repositories.local)].sort
  end
end


describe Rake::Task, " uninstall" do
  it "should be local task" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    task("install").invoke
    in_original_dir project("foo:bar").base_dir do
      task("uninstall").invoke
      FileList[repositories.local + "/**/*"].reject { |f| File.directory?(f) }.sort.should == [
        File.expand_path("foo/foo/1.0/foo-1.0.zip", repositories.local),
        File.expand_path("foo/foo/1.0/foo-1.0.pom", repositories.local)].sort
    end
  end

  it "should be recursive task" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    task("install").invoke
    task("uninstall").invoke
    FileList[repositories.local + "/**/*"].reject { |f| File.directory?(f) }.sort.should be_empty
  end
end


describe Rake::Task, " upload" do
  before do
    repositories.release_to = "file://#{File.expand_path('remote')}"
  end
  
  it "should be local task" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    in_original_dir project("foo:bar").base_dir do
      lambda { task("upload").invoke }.should run_task("foo:bar:upload").but_not("foo:upload")
    end
  end

  it "should be recursive task" do
    define "foo", :version=>"1.0" do
      mkpath "target/classes" ; package
      define("bar") { mkpath "bar/target/classes" ; package }
    end
    lambda { task("upload").invoke }.should run_tasks("foo:upload", "foo:bar:upload")
  end

  it "should upload artifact and POM" do
    define("foo", :version=>"1.0") { package :jar }
    task("upload").invoke
    { "remote/foo/foo/1.0/foo-1.0.jar"=>project("foo").package(:jar),
      "remote/foo/foo/1.0/foo-1.0.pom"=>project("foo").package(:jar).pom }.each do |upload, package|
      read(upload).should eql(read(package))
    end
  end

  it "should upload signatures for artifact and POM" do
    define("foo", :version=>"1.0") { package :jar }
    task("upload").invoke
    { "remote/foo/foo/1.0/foo-1.0.jar"=>project("foo").package(:jar),
      "remote/foo/foo/1.0/foo-1.0.pom"=>project("foo").package(:jar).pom }.each do |upload, package|
      read("#{upload}.md5").split.first.should eql(Digest::MD5.hexdigest(read(package)))
      read("#{upload}.sha1").split.first.should eql(Digest::SHA1.hexdigest(read(package)))
    end
  end
end


describe "packaging", :shared=>true do
  it "should create artifact of proper type" do
    packaging = self.packaging
    package_type = respond_to?(:package_type) ? self.package_type : packaging
    define("foo", :version=>"1.0") { package(packaging) }
    project("foo").package(packaging).type.should eql(package_type)
  end

  it "should create file with proper extension" do
    packaging = self.packaging
    package_type = respond_to?(:package_type) ? self.package_type : packaging
    define("foo", :version=>"1.0") { package(packaging) }
    project("foo").package(packaging).to_s.pathmap("%x").should eql(".#{package_type}")
  end

  it "should always return same task for the same package" do
    packaging = self.packaging
    define "foo", :version=>"1.0" do
      package(packaging)
      package(packaging, :id=>"other")
      package(packaging, :classifier=>"extra")
    end
    project("foo").packages.should eql([
      project("foo").package(packaging),
      project("foo").package(packaging, :id=>"other"),
      project("foo").package(packaging, :classifier=>"extra")].uniq)
  end

  it "should complain if option not known" do
    packaging = self.packaging
    lambda do
      define("foo", :version=>"1.0") { package(packaging, :unknown_option=>true) }
    end.should raise_error(ArgumentError, /no such option/)
  end

  it "should respond to with() and return self" do
    packaging = self.packaging
    define("foo", :version=>"1.0") { package(packaging) }
    project("foo").package(packaging).with({}).should be(project("foo").package(packaging))
  end

  it "should respond to with() and complain if unknown option" do
    packaging = self.packaging
    define("foo", :version=>"1.0") { package(packaging) }
    lambda do
      project("foo").package(packaging).with(:unknown_option=>true)
    end.should raise_error(ArgumentError, /does not support the option/)
  end
end


describe "package_with_manifest", :shared=>true do
  define_method(:long_line) { "No line may be longer than 72 bytes (not characters), in its UTF8-encoded form. If a value would make the initial line longer than this, it should be continued on extra lines (each starting with a single SPACE)." }

  def package_with_manifest(manifest = nil)
    packaging = self.packaging
    @project = define("foo", :version=>"1.2") do
      build { mkpath "target/classes" }
      package packaging
      package(packaging).with(:manifest=>manifest) unless manifest.nil?
    end
  end

  def inspect_manifest()
    package = project("foo").package(packaging)
    package.invoke
    Zip::ZipFile.open(package.to_s) do |zip|
      sections = zip.file.read("META-INF/MANIFEST.MF").split("\n\n").map do |section|
          section.split("\n").each { |line| line.length.should < 72 }.
            inject([]) { |merged, line|
              if line[0] == 32
                merged.last << line[1..-1]
              else
                merged << line
              end
              merged
            }.map { |line| line.split(/: /) }.
            inject({}) { |map, (name, value)| map.merge(name=>value) }
        end
      yield sections
    end
  end

  it "should include default header when no options specified" do
    ENV["USER"] = "MysteriousJoe"
    package_with_manifest # Nothing for default.
    inspect_manifest do |sections|
      sections.size.should be(1)
      sections.first.should == {
        "Manifest-Version"        => "1.0",
        "Created-By"              => "Buildr",
        "Implementation-Title"    =>@project.name,
        "Implementation-Version"  =>"1.2",
        "Build-Jdk"               =>Java.version,
        "Build-By"                =>"MysteriousJoe"
      }
    end
  end

  it "should not exist when manifest=false" do
    package_with_manifest false
    @project.package(packaging).invoke
    Zip::ZipFile.open(@project.package(packaging).to_s) do |zip|
      zip.file.exist?("META-INF/MANIFEST.MF").should be_false
    end
  end

  it "should map manifest from hash" do
    package_with_manifest "Foo"=>1, :bar=>"Bar"
    inspect_manifest do |sections|
      sections.size.should be(1)
      sections.first["Manifest-Version"].should eql("1.0")
      sections.first["Created-By"].should eql("Buildr")
      sections.first["Foo"].should eql("1")
      sections.first["bar"].should eql("Bar")
    end
  end

  it "should end hash manifest with EOL" do
    package_with_manifest "Foo"=>1, :bar=>"Bar"
    package = project("foo").package(packaging)
    package.invoke
    Zip::ZipFile.open(package.to_s) { |zip| zip.file.read("META-INF/MANIFEST.MF")[-1].should == ?\n }
  end

  it "should break hash manifest lines longer than 72 characters using continuations" do
    package_with_manifest "foo"=>long_line
    package = project("foo").package(packaging)
    inspect_manifest do |sections|
      sections.first["foo"].should == long_line
    end
  end

  it "should map manifest from array" do
    package_with_manifest [ { :foo=>"first" }, { :bar=>"second" } ]
    inspect_manifest do |sections|
      sections.size.should be(2)
      sections.first["Manifest-Version"].should eql("1.0")
      sections.first["foo"].should eql("first")
      sections.last["bar"].should eql("second")
    end
  end

  it "should end array manifest with EOL" do
    package_with_manifest [ { :foo=>"first" }, { :bar=>"second" } ]
    package = project("foo").package(packaging)
    package.invoke
    Zip::ZipFile.open(package.to_s) { |zip| zip.file.read("META-INF/MANIFEST.MF")[-1].should == ?\n }
  end

  it "should break array manifest lines longer than 72 characters using continuations" do
    package_with_manifest ["foo"=>long_line]
    package = project("foo").package(packaging)
    inspect_manifest do |sections|
      sections.first["foo"].should == long_line
    end
  end

  it "should put Name: at beginning of section" do
    package_with_manifest [ {}, { "Name"=>"first", :Foo=>"first", :bar=>"second" } ]
    package = project("foo").package(packaging)
    package.invoke
    Zip::ZipFile.open(package.to_s) do |zip|
      sections = zip.file.read("META-INF/MANIFEST.MF").split(/\n\n/)
      sections[1].split("\n").first.should =~ /^Name: first/
    end
  end

  it "should create manifest from proc" do
    package_with_manifest lambda { "Meta: data" }
    inspect_manifest do |sections|
      sections.size.should be(1)
      sections.first["Manifest-Version"].should eql("1.0")
      sections.first["Meta"].should eql("data")
    end
  end

  it "should create manifest from file" do
    write "MANIFEST.MF", "Meta: data"
    package_with_manifest "MANIFEST.MF"
    inspect_manifest do |sections|
      sections.size.should be(1)
      sections.first["Manifest-Version"].should eql("1.0")
      sections.first["Meta"].should eql("data")
    end
  end

  it "should create manifest from task" do
    file "MANIFEST.MF" do |task|
      write task.to_s, "Meta: data"
    end
    package_with_manifest "MANIFEST.MF"
    inspect_manifest do |sections|
      sections.size.should be(1)
      sections.first["Manifest-Version"].should eql("1.0")
      sections.first["Meta"].should eql("data")
    end
  end

  it "should respond to with() and accept manifest" do
    write "DISCLAIMER"
    mkpath "target/classes"
    packaging = self.packaging
    define("foo", :version=>"1.0") { package(packaging).with :manifest=>{"Foo"=>"data"} }
    inspect_manifest { |sections| sections.first["Foo"].should eql("data") }
  end

  it "should include META-INF directory" do
    packaging = self.packaging
    package = define("foo", :version=>"1.0") { package(packaging) }.packages.first
    package.invoke
    Zip::ZipFile.open(package.to_s) do |zip|
      zip.entries.map(&:to_s).should include("META-INF/")
    end
  end
end


describe "package_with_meta_inf", :shared=>true do

  def package_with_meta_inf(meta_inf = nil)
    packaging = self.packaging
    @project = Buildr.define("foo", :version=>"1.2") do
      build { mkpath "target/classes" }
      package packaging
      package(packaging).with(:meta_inf=>meta_inf) if meta_inf
    end
  end

  def inspect_meta_inf()
    package = project("foo").package(packaging)
    package.invoke
    assumed = Array(meta_inf())
    Zip::ZipFile.open(package.to_s) do |zip|
      entries = zip.entries.map(&:to_s).select { |f| File.dirname(f) == "META-INF" }.map { |f| File.basename(f) }
      assumed.each { |f| entries.should include(f) }
      yield entries - assumed if block_given?
    end
  end

  it "should default to LICENSE file" do
    write "LICENSE"
    package_with_meta_inf
    inspect_meta_inf { |files| files.should eql(["LICENSE"]) }
  end

  it "should be empty if no LICENSE file" do
    package_with_meta_inf
    inspect_meta_inf { |files| files.should be_empty }
  end

  it "should include file specified by :meta_inf option" do
    write "README"
    package_with_meta_inf "README"
    inspect_meta_inf { |files| files.should eql(["README"]) }
  end

  it "should include files specified by :meta_inf option" do
    files = ["README", "DISCLAIMER"].each { |file| write file }
    package_with_meta_inf files
    inspect_meta_inf { |files| files.should eql(files) }
  end

  it "should include file task specified by :meta_inf option" do
    file("README") { |task| write task.to_s }
    package_with_meta_inf file("README")
    inspect_meta_inf { |files| files.should eql(["README"]) }
  end

  it "should include file tasks specified by :meta_inf option" do
    files = ["README", "DISCLAIMER"].each { |file| file(file) { |task| write task.to_s } }
    package_with_meta_inf files.map { |f| file(f) }
    inspect_meta_inf { |files| files.should eql(files) }
  end

  it "should complain if cannot find file" do
    package_with_meta_inf "README"
    lambda { inspect_meta_inf }.should raise_error(RuntimeError, /README/)
  end

  it "should complain if cannot build task" do
    file("README")  { fail "Failed" }
    package_with_meta_inf "README"
    lambda { inspect_meta_inf }.should raise_error(RuntimeError, /Failed/)
  end

  it "should respond to with() and accept manifest and meta_inf" do
    write "DISCLAIMER"
    mkpath "target/classes"
    packaging = self.packaging ; define("foo", :version=>"1.0") { package(packaging).with :meta_inf=>"DISCLAIMER" }
    inspect_meta_inf { |files| files.should eql(["DISCLAIMER"]) }
  end
end


describe Packaging, " zip" do
  define_method(:packaging) { :zip }
  it_should_behave_like "packaging"

  it "should not include META-INF directory" do
    define("foo", :version=>"1.0") { package(:zip) }
    project("foo").package(:zip).invoke
    Zip::ZipFile.open(project("foo").package(:zip).to_s) do |zip|
      zip.entries.map(&:to_s).should_not include("META-INF/")
    end
  end
end


describe Packaging, " jar" do
  define_method(:packaging) { :jar }
  it_should_behave_like "packaging"
  it_should_behave_like "package_with_manifest"
  define_method(:meta_inf)  { "MANIFEST.MF" }
  it_should_behave_like "package_with_meta_inf"

  it "should use files from compile directory if nothing included" do
    write "src/main/java/Test.java", "class Test {}"
    define("foo", :version=>"1.0") { package(:jar) }
    project("foo").package(:jar).invoke
    Zip::ZipFile.open(project("foo").package(:jar).to_s) do |jar|
      jar.entries.map(&:to_s).sort.should include("META-INF/MANIFEST.MF", "Test.class")
    end
  end

  it "should use files from resources directory if nothing included" do
    write "src/main/resources/test/important.properties"
    define("foo", :version=>"1.0") { package(:jar) }
    project("foo").package(:jar).invoke
    Zip::ZipFile.open(project("foo").package(:jar).to_s) do |jar|
      jar.entries.map(&:to_s).sort.should include("test/important.properties")
    end
  end

  it "should include class directories" do
    write "src/main/java/code/Test.java", "package code ; class Test {}"
    define("foo", :version=>"1.0") { package(:jar) }
    project("foo").package(:jar).invoke
    Zip::ZipFile.open(project("foo").package(:jar).to_s) do |jar|
      jar.entries.map(&:to_s).sort.should include("code/")
    end
  end

  it "should include resource files starting with dot" do
    write "src/main/resources/test/.config"
    define("foo", :version=>"1.0") { package(:jar) }
    project("foo").package(:jar).invoke
    Zip::ZipFile.open(project("foo").package(:jar).to_s) do |jar|
      jar.entries.map(&:to_s).sort.should include("test/.config")
    end
  end

  it "should include empty resource directories" do
    mkpath "src/main/resources/empty"
    define("foo", :version=>"1.0") { package(:jar) }
    project("foo").package(:jar).invoke
    Zip::ZipFile.open(project("foo").package(:jar).to_s) do |jar|
      jar.entries.map(&:to_s).sort.should include("empty/")
    end
  end
end


describe Packaging, " war" do
  define_method(:packaging) { :war }
  it_should_behave_like "packaging"
  it_should_behave_like "package_with_manifest"
  define_method(:meta_inf)  { "MANIFEST.MF" }
  it_should_behave_like "package_with_meta_inf"

  def make_jars()
    artifact("group:id:jar:1.0") { |t| write t.to_s }
    artifact("group:id:jar:2.0") { |t| write t.to_s }
  end

  def inspect_war()
    project("foo").package(:war).invoke
    Zip::ZipFile.open(project("foo").package(:war).to_s) do |war|
      yield war.entries.map(&:to_s).sort
    end
  end

  it "should use files from webapp directory if nothing included" do
    write "src/main/webapp/test.html"
    define("foo", :version=>"1.0") { package(:war) }
    inspect_war { |files| files.should include("test.html") }
  end

  it "should ignore webapp directory if missing" do
    define("foo", :version=>"1.0") { package(:war) }
    inspect_war { |files| files.should eql(["META-INF/", "META-INF/MANIFEST.MF"]) }
  end

  it "should accept files from :classes option" do
    write "src/main/java/Test.java", "class Test {}"
    write "classes/test"
    define("foo", :version=>"1.0") { package(:war).with(:classes=>"classes") }
    inspect_war { |files| files.should include("WEB-INF/classes/test") }
  end

  it "should use files from compile directory if nothing included" do
    write "src/main/java/Test.java", "class Test {}"
    define("foo", :version=>"1.0") { package(:war) }
    inspect_war { |files| files.should include("WEB-INF/classes/Test.class") }
  end

  it "should ignore compile directory if no source files to compile" do
    define("foo", :version=>"1.0") { package(:war) }
    inspect_war { |files| files.should_not include("target/classes") }
  end

  it "should include only specified classes directories" do
    write "src/main/java"
    define("foo", :version=>"1.0") { package(:war).with :classes=>_("additional") }
    project("foo").package(:war).classes.should_not include(project("foo").file("target/classes"))
    project("foo").package(:war).classes.should include(project("foo").file("additional"))
  end

  it "should use files from resources directory if nothing included" do
    write "src/main/resources/test/important.properties"
    define("foo", :version=>"1.0") { package(:war) }
    inspect_war { |files| files.should include("WEB-INF/classes/test/important.properties") }
  end

  it "should include empty resource directories" do
    mkpath "src/main/resources/empty"
    define("foo", :version=>"1.0") { package(:war) }
    inspect_war { |files| files.should include("WEB-INF/classes/empty/") }
  end

  it "should accept file from :libs option" do
    make_jars
    define("foo", :version=>"1.0") { package(:war).with(:libs=>"group:id:jar:1.0") }
    inspect_war { |files| files.should include("META-INF/MANIFEST.MF", "WEB-INF/lib/id-1.0.jar") }
  end

  it "should accept file from :libs option" do
    make_jars
    define("foo", :version=>"1.0") { package(:war).with(:libs=>["group:id:jar:1.0", "group:id:jar:2.0"]) }
    inspect_war { |files| files.should include("META-INF/MANIFEST.MF", "WEB-INF/lib/id-1.0.jar", "WEB-INF/lib/id-2.0.jar") }
  end

  it "should use artifacts from compile classpath if no libs specified" do
    make_jars
    define("foo", :version=>"1.0") { compile.with "group:id:jar:1.0", "group:id:jar:2.0" ; package(:war) }
    inspect_war { |files| files.should include("META-INF/MANIFEST.MF", "WEB-INF/lib/id-1.0.jar", "WEB-INF/lib/id-2.0.jar") }
  end

  it "should include only specified libraries" do
    define "foo", :version=>"1.0" do
      compile.with "group:id:jar:1.0"
      package(:war).with :libs=>"additional:id:jar:1.0"
    end
    project("foo").package(:war).libs.should_not include(artifact("group:id:jar:1.0"))
    project("foo").package(:war).libs.should include(artifact("additional:id:jar:1.0"))
  end

end


describe Packaging, " aar" do
  define_method(:packaging) { :aar }
  it_should_behave_like "packaging"
  it_should_behave_like "package_with_manifest"
  define_method(:meta_inf)  { ["MANIFEST.MF", "services.xml"] }
  it_should_behave_like "package_with_meta_inf"

  setup { write "src/main/axis2/services.xml" }

  def make_jars()
    artifact("group:id:jar:1.0") { |t| write t.to_s }
    artifact("group:id:jar:2.0") { |t| write t.to_s }
  end

  def inspect_aar()
    project("foo").package(:aar).invoke
    Zip::ZipFile.open(project("foo").package(:aar).to_s) do |aar|
      yield aar.entries.map(&:to_s).sort
    end
  end

  it "should automatically include services.xml and any *.wsdl files under src/main/axis2" do
    write "src/main/axis2/my-service.wsdl"
    define("foo", :version=>"1.0") { package(:aar) }
    inspect_aar { |files| files.should include("META-INF/MANIFEST.MF", "META-INF/services.xml", "META-INF/my-service.wsdl") }
  end

  it "should accept files from :include option" do
    write "test"
    define("foo", :version=>"1.0") { package(:aar).include "test" }
    inspect_aar { |files| files.should include("META-INF/MANIFEST.MF", "test") }
  end

  it "should use files from compile directory if nothing included" do
    write "src/main/java/Test.java", "class Test {}"
    define("foo", :version=>"1.0") { package(:aar) }
    inspect_aar { |files| files.should include("Test.class") }
  end

  it "should use files from resources directory if nothing included" do
    write "src/main/resources/test/important.properties"
    define("foo", :version=>"1.0") { package(:aar) }
    inspect_aar { |files| files.should include("test/important.properties") }
  end

  it "should include empty resource directories" do
    mkpath "src/main/resources/empty"
    define("foo", :version=>"1.0") { package(:aar) }
    inspect_aar { |files| files.should include("empty/") }
  end

  it "should accept file from :libs option" do
    make_jars
    define("foo", :version=>"1.0") { package(:aar).with :libs=>"group:id:jar:1.0" }
    inspect_aar { |files| files.should include("META-INF/MANIFEST.MF", "lib/id-1.0.jar") }
  end

  it "should accept file from :libs option" do
    make_jars
    define("foo", :version=>"1.0") { package(:aar).with :libs=>["group:id:jar:1.0", "group:id:jar:2.0"] }
    inspect_aar { |files| files.should include("META-INF/MANIFEST.MF", "lib/id-1.0.jar", "lib/id-2.0.jar") }
  end

  it "should NOT use artifacts from compile classpath if no libs specified" do
    make_jars
    define("foo", :version=>"1.0") { compile.with "group:id:jar:1.0", "group:id:jar:2.0" ; package(:aar) }
    inspect_aar { |files| files.should include("META-INF/MANIFEST.MF") }
  end

  it "should return all libraries from libs attribute" do
    define "foo", :version=>"1.0" do
      compile.with "group:id:jar:1.0"
      package(:aar).with :libs=>"additional:id:jar:1.0"
    end
    project("foo").package(:aar).libs.should_not include(artifact("group:id:jar:1.0"))
    project("foo").package(:aar).libs.should include(artifact("additional:id:jar:1.0"))
  end

end


describe Packaging, " tar" do
  define_method(:packaging) { :tgz }
  it_should_behave_like "packaging"
end


describe Packaging, " tgz" do
  define_method(:packaging) { :tgz }
  it_should_behave_like "packaging"
end


describe Packaging, " sources" do
  define_method(:packaging) { :sources }
  define_method(:package_type) { :zip }
  it_should_behave_like "packaging"

  it "should create package of type :zip and classifier 'sources'" do
    package = define("foo", :version=>"1.0") { package(:sources) }.packages.first
    package.type.should eql(:zip)
    package.classifier.should eql("sources")
    package.name.pathmap("%f").should eql("foo-1.0-sources.zip")
  end

  it "should contain source files" do
    write "src/main/java/Source.java"
    package = define("foo", :version=>"1.0") { package(:sources) }.packages.first
    package.invoke
    package.should contain("Source.java")
  end
end


describe Packaging, " javadoc" do
  define_method(:packaging) { :javadoc }
  define_method(:package_type) { :zip }
  it_should_behave_like "packaging"

  it "should create package of type :zip and classifier 'javadoc'" do
    package = define("foo", :version=>"1.0") { package(:javadoc) }.packages.first
    package.type.should eql(:zip)
    package.classifier.should eql("javadoc")
    package.name.pathmap("%f").should eql("foo-1.0-javadoc.zip")
  end

  it "should contain Javadocs" do
    write "src/main/java/Source.java", "public class Source {}"
    package = define("foo", :version=>"1.0") { package(:javadoc) }.packages.first
    package.invoke
    package.should contain("Source.html", "index.html")
  end

  it "should use project description in window title" do
    write "src/main/java/Source.java", "public class Source {}"
    desc "My Project"
    package = define("foo", :version=>"1.0") { package(:javadoc) }.packages.first
    package.invoke
    package.entry("index.html").should contain("My Project")
  end
end


describe "package_with_", :shared=>true do

  def specify(options = {})
    method = "package_with_#{packaging}" 
    write "src/main/java/Source.java"
    write "baz/src/main/java/Source.java"
    define "foo", :version=>"1.0" do
      send method, options
      define "bar" ; define "baz"
    end
  end

  def sources_in(*names)
    projects.each do |project|
      if names.include?(project.name)
        project.packages.first.name.should =~ /-#{packaging}.zip/
      else
        project.packages.should be_empty
      end
    end
  end

  it "should create sources only for projects that have source files" do
    specify
    sources_in "foo", "foo:baz"
  end

  it "should limit to project specified by :only" do
    specify :only=>"baz"
    sources_in "foo:baz"
  end

  it "should limit to projects specified by :only" do
    specify :only=>["baz"]
    sources_in "foo:baz"
  end

  it "should ignore project specified by :except" do
    specify :except=>"baz"
    sources_in "foo"
  end

  it "should ignore projects specified by :except" do
    specify :except=>["baz"]
    sources_in "foo" 
  end
end

describe "package_with_sources" do
  it_should_behave_like "package_with_"
  define_method(:packaging) { :sources }
end

describe "package_with_javadoc" do
  it_should_behave_like "package_with_"
  define_method(:packaging) { :javadoc }
end
