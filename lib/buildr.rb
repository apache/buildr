# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.


$KCODE = 'utf8'
# in order to work around a bug in jruby (1.0.1 and trunk as of oct11, 2007)
# needle and net/ssh need to be loaded before -anything- else. please see
# http://jira.codehaus.org/browse/JRUBY-1188 for more info.
require 'needle'
require 'net/ssh'

require 'highline'
require 'highline/import'
require 'builder' # A different kind of buildr, one we use to create XML.


module Buildr
  VERSION = '1.3.0'.freeze # unless const_defined?(:VERSION)
end

require File.join(File.dirname(__FILE__), 'core')
require File.join(File.dirname(__FILE__), 'tasks')
require File.join(File.dirname(__FILE__), 'java')
require File.join(File.dirname(__FILE__), 'ide')


# Methods defined in Buildr are both instance methods (e.g. when included in Project)
# and class methods when invoked like Buildr.artifacts().
module Buildr ; extend self ; end
# The Buildfile object (self) has access to all the Buildr methods and constants.
class << self ; include Buildr ; end
class Object #:nodoc:
  Buildr.constants.each { |c| const_set c, Buildr.const_get(c) unless const_defined?(c) }
end

# Prevent RSpec runner from running at_exit.
require 'spec'
Spec.run = true
