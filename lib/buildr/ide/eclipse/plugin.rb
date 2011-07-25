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

module Buildr
  module Eclipse
    module Plugin
      include Extension

      NATURE    = 'org.eclipse.pde.PluginNature'
      CONTAINER = 'org.eclipse.pde.core.requiredPlugins'
      BUILDERS   = ['org.eclipse.pde.ManifestBuilder', 'org.eclipse.pde.SchemaBuilder']

      after_define do |project|
        eclipse = project.eclipse

        # smart defaults
        if eclipse.natures.empty? && (
            (File.exists? project.path_to("plugin.xml")) ||
            (File.exists? project.path_to("OSGI-INF")) ||
            (File.exists?(project.path_to("META-INF/MANIFEST.MF")) && File.read(project.path_to("META-INF/MANIFEST.MF")).match(/^Bundle-SymbolicName:/)))
          eclipse.natures = [NATURE, Buildr::Eclipse::Java::NATURE]
          eclipse.classpath_containers = [CONTAINER, Buildr::Eclipse::Java::CONTAINER] if eclipse.classpath_containers.empty?
          eclipse.builders = BUILDERS + [Buildr::Eclipse::Java::BUILDER] if eclipse.builders.empty?
        end

        # :plugin nature explicitly set
        if eclipse.natures.include? :plugin
          unless eclipse.natures.include? NATURE
            # plugin nature must be before java nature
            eclipse.natures += [Buildr::Eclipse::Java::NATURE] unless eclipse.natures.include? Buildr::Eclipse::Java::NATURE
            index = eclipse.natures.index(Buildr::Eclipse::Java::NATURE) || -1
            eclipse.natures = eclipse.natures.insert(index, NATURE)
          end
          unless eclipse.classpath_containers.include? CONTAINER
            # plugin container must be before java container
            index = eclipse.classpath_containers.index(Buildr::Eclipse::Java::CONTAINER) || -1
            eclipse.classpath_containers = eclipse.classpath_containers.insert(index, CONTAINER)
          end
          unless (eclipse.builders.include?(BUILDERS[0]) && eclipse.builders.include?(BUILDERS[1]))
            # plugin builder must be before java builder
            index = eclipse.classpath_containers.index(Buildr::Eclipse::Java::BUILDER) || -1
            eclipse.builders = eclipse.builders.insert(index, BUILDERS[1]) unless eclipse.builders.include? BUILDERS[1]
            index = eclipse.classpath_containers.index(BUILDERS[1]) || -1
            eclipse.builders = eclipse.builders.insert(index, BUILDERS[0]) unless eclipse.builders.include? BUILDERS[0]
          end
        end
      end

    end
  end
end

class Buildr::Project
  include Buildr::Eclipse::Plugin
end
