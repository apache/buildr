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


require 'buildr/shell'
require 'buildr/java/commands'

module Buildr
  module Scala
    class ScalaShell < Buildr::Shell::Base
      include Buildr::Shell::JavaRebel
      
      class << self
        def lang
          :scala
        end
        
        def to_sym
          :scala
        end
      end
      
      def launch
        cp = project.compile.dependencies + 
          Scalac.dependencies +
          [project.path_to(:target, :classes)]
        
        props = {
          'env.classpath' => cp.join(File::PATH_SEPARATOR),
          'scala.home' => Scalac.scala_home
        }
        
        Java::Commands.java 'scala.tools.nsc.MainGenericRunner', {
          :properties => props.merge(rebel_props(project)),
          :classpath => cp,
          :java_args => rebel_args
        }
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Scala::ScalaShell
