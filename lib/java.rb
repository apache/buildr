require 'java/compile'
require 'java/test'
require 'java/packaging'

class Buildr::Project
  include Buildr::Test
  include Buildr::Java::Packaging
  include Buildr::Javadoc
end
