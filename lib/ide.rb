require 'ide/eclipse'
require 'ide/idea'

class Buildr::Project
  include Buildr::Eclipse, Buildr::Idea
end
