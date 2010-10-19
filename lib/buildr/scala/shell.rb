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
      include Buildr::JRebel

      specify :name => :scala, :languages => [:scala]

      def launch(task)
        cp = project.compile.dependencies + Scalac.dependencies +  [project.path_to(:target, :classes)]

        java_args = task.options[:java_args] || (ENV['JAVA_OPTS'] || ENV['JAVA_OPTIONS']).to_s.split

        props = jrebel_props(project)
        props = props.merge(task.options[:properties]) if task.options[:properties]
        props = props.merge 'scala.home' => Scalac.scala_home

        jline = [File.expand_path("lib/jline.jar", Scalac.scala_home)].find_all { |f| File.exist? f }

        Java::Commands.java 'scala.tools.nsc.MainGenericRunner',
                            '-cp', cp.join(File::PATH_SEPARATOR),
        {
          :properties => props,
          :classpath => Scalac.dependencies + jline,
          :java_args => jrebel_argss
        }
      end
    end
  end
end

Buildr::Shell.providers << Buildr::Scala::ScalaShell
