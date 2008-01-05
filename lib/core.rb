require 'core/application'
require 'core/project'
require 'core/environment'
require 'core/help'
require 'core/build'
require 'core/package'
require 'core/compile'
require 'core/test'
require 'core/checks'
require 'core/generate'

class Buildr::Project
  # Project has visibility to everything in the Buildr namespace. what follows are specific extensions.
  # Put first, so other extensions can over-ride Buildr methods.
  include Buildr
  include Buildr::Build
  include Buildr::Compile
  include Buildr::Test
  include Buildr::Package
  include Buildr::Checks
end
