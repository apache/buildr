require File.expand_path('../spec_helpers', File.dirname(__FILE__))
Sandbox.require_optional_extension 'buildr/checkstyle'
artifacts(Buildr::Checkstyle::dependencies).map(&:invoke)

CHECKS_CONTENT = <<CHECKS
<?xml version="1.0"?>
<!DOCTYPE module PUBLIC
            "-//Puppy Crawl//DTD Check Configuration 1.2//EN"
            "http://www.puppycrawl.com/dtds/configuration_1_2.dtd">
<module name="Checker">
</module>
CHECKS
GOOD_CONTENT = <<GOOD
public final class SomeClass {
}
GOOD

describe Buildr::Checkstyle do

  before do
    # Reloading the extension because the sandbox removes all its actions
    Buildr.module_eval { remove_const :Checkstyle }
    load File.expand_path('../addon/buildr/checkstyle.rb')
    @tool_module = Buildr::Checkstyle

    write 'src/main/java/SomeClass.java', GOOD_CONTENT
    write 'src/main/etc/checkstyle/checks.xml', CHECKS_CONTENT
  end

  it 'should generate an XML report' do
    define 'foo'
    task('foo:checkstyle:xml').invoke
    file(project('foo')._('reports/checkstyle/checkstyle.xml')).should exist
  end

  it 'should generate an HTML report' do
    define 'foo'
    task('foo:checkstyle:html').invoke
    file(project('foo')._('reports/checkstyle/checkstyle.html')).should exist
  end

end
