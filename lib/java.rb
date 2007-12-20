require 'java/compile'
require 'java/test'
require 'java/packaging'

class Buildr::Project
  include Buildr::Java::Compile
  include Buildr::Test
  include Buildr::Java::Packaging
end
