require File.join(File.dirname(__FILE__), 'sandbox')


describe "Local directory build task" do
  it "should execute build task for current project" do
    define "foobar"
    lambda { task("build").invoke }.should run_task("foobar:build")
  end

  it "should not execute build task for other projects" do
    define "foobar", :base_dir=>"elsewhere"
    lambda { task("build").invoke }.should_not run_task("foobar:build")
  end
end


describe Project, " build task" do
  it "should execute build task for sub-project" do
    define("foo") { define "bar" }
    lambda { task("foo:build").invoke }.should run_task("foo:bar:build")
  end

  it "should not execute build task of other projects" do
    define "foo"
    define "bar"
    lambda { task("foo:build").invoke }.should_not run_task("bar:build")
  end

  it "should be accessible as build method" do
    define "boo"
    project("boo").build.should be(task("boo:build"))
  end
end
