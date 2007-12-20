require 'core/application'
require 'core/project'
require 'core/build'
require 'core/help'
require 'core/generate'

class Buildr::Project
  # Project has visibility to everything in the Buildr namespace. what follows are specific extensions.
  # Put first, so other extensions can over-ride Buildr methods.
  include Buildr
  include Buildr::Build, Buildr::Checks
end
