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

require 'buildr/run'
require 'buildr/java/commands'
require 'buildr/core/util'

module Buildr
  module Run

    class JavaRunner < Base
      include Shell::JavaRebel

      specify :name => :java, :languages => [:java, :scala, :groovy, :clojure]

      def run(task)
        fail "Missing :main option" unless task.options[:main]
        cp = project.compile.dependencies + [project.path_to(:target, :classes)] + task.classpath
        Java::Commands.java(task.options[:main], {
          :properties => rebel_props(project).merge(task.options[:properties] || {}),
          :classpath => cp,
          :java_args => rebel_args + (task.options[:java_args] || [])
        })
      end
    end # JavaRunnner

  end
end

Buildr::Run.runners << Buildr::Run::JavaRunner

