require File.join(File.dirname(__FILE__), 'sandbox')


describe "Circular dependency" do
  it "should raise error for foo=>bar=>foo" do
    task "foo"=>"bar"
    task "bar"=>"foo"
    lambda { task("foo").invoke }.should raise_error(RuntimeError, /foo=>bar=>foo/)
  end

  it "should raise error for foo=>bar=>baz=>foo" do
    task "foo"=>"bar"
    task "bar"=>"baz"
    task "baz"=>"foo"
    lambda { task("foo").invoke }.should raise_error(RuntimeError, /foo=>bar=>baz=>foo/)
  end

  it "should not fail on complex dependencies" do
    task "foo"=>"bar"
    task "bar"=>"baz"
    task "baz"
    lambda { task("foo").invoke }.should_not raise_error
  end

  it "should catch circular dependencies in multitask" do
    multitask "foo"=>["bar", "baz"]
    task "bar"
    task "baz"=>"foo"
    lambda { task("foo").invoke }.should raise_error(RuntimeError, /foo=>baz=>foo/)
  end
end
