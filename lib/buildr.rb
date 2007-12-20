# in order to work around a bug in jruby (1.0.1 and trunk as of oct11, 2007)
# needle and net/ssh need to be loaded before -anything- else. please see
# http://jira.codehaus.org/browse/JRUBY-1188 for more info.
require 'needle'
require 'net/ssh'

require "highline"
require "highline/import"
# &:symbol goodness.
require "facet/symbol/to_proc"
# blank? on string and nil
require "facet/string/blank"
require "facet/nilclass/blank"
# x.in?(y) is better than y.include?(x)
require "facet/kernel/in"
# Allows binding[]
require "facet/binding"
# What it says.
require "facet/kernel/__DIR__"
require "facet/kernel/instance_exec"
require "facet/module/alias_method_chain"
require "facet/module/memoize"
require "facet/array/head"
require "facet/string/starts_with"
require "facet/openobject"
require "facets/core/kernel/tap"
require "facets/core/enumerable/uniq_by"
# A different kind of buildr, one we use to create XML.
require "builder"


module Buildr
  VERSION = "1.2.11".freeze # unless const_defined?(:VERSION)

end

require 'core'
require 'tasks'
require 'java'
require 'ide'


# Methods defined in Buildr are both instance methods (e.g. when included in Project)
# and class methods when invoked like Buildr.artifacts().
module Buildr ; extend self ; end
# The Buildfile object (self) has access to all the Buildr methods and constants.
class << self ; include Buildr ; end
class Object #:nodoc:
  Buildr.constants.each { |c| const_set c, Buildr.const_get(c) unless const_defined?(c) }
end
