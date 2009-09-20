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

module Buildr
  module Groovy
    class GroovySH < Buildr::Shell::Base
      SUFFIX = if Util.win_os? then '.bat' else '' end
      
      class << self
        def lang
          :groovy
        end
      end
      
      def launch
        fail 'Are we forgetting something? GROOVY_HOME not set.' unless groovy_home
        
        cp = project.compile.dependencies.join(File::PATH_SEPARATOR) + 
          File::PATH_SEPARATOR + project.path_to(:target, :classes)
        
        cmd_args = " -classpath '#{cp}'"
        trace "groovysh #{cmd_args}"
        system(File.expand_path("bin#{File::SEPARATOR}groovysh#{SUFFIX}", groovy_home) + cmd_args)
      end
      
    private
      def groovy_home
        @home ||= ENV['GROOVY_HOME']
      end
    end
  end
end

Buildr::ShellProviders << Buildr::Groovy::GroovySH
