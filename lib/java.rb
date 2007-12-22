require 'java/compilers'
require 'java/test_frameworks'
require 'java/packaging'

class Buildr::Project
  include Buildr::Test
  include Buildr::Java::Packaging
  include Buildr::Javadoc
end
