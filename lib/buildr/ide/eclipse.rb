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


require 'buildr/core/project'
require 'buildr/packaging'


module Buildr
  module Eclipse #:nodoc:

    include Extension

    first_time do
      # Global task "eclipse" generates artifacts for all projects.
      desc "Generate Eclipse artifacts for all projects"
      Project.local_task "eclipse"=>"artifacts"
    end

    before_define do |project|
      project.recursive_task("eclipse")
    end

    after_define do |project|
      eclipse = project.task("eclipse")
      # We need paths relative to the top project's base directory.
      root_path = lambda { |p| f = lambda { |p| p.parent ? f[p.parent] : p.base_dir } ; f[p] }[project]

      # We want the Eclipse files changed every time the Buildfile changes, but also anything loaded by
      # the Buildfile (buildr.rb, separate file listing dependencies, etc), so we add anything required
      # after the Buildfile. So which don't know where Buildr shows up exactly, ignore files that show
      # in $LOADED_FEATURES that we cannot resolve.
      sources = Buildr.application.build_files.map { |file| File.expand_path(file) }.select { |file| File.exist?(file) }
      sources << File.expand_path(Buildr.application.buildfile, root_path) if Buildr.application.buildfile

      # Check if project has scala facet
      scala = project.compile.language == :scala

      # Only for projects that we support
      supported_languages = [:java, :scala]
      supported_packaging = %w(jar war rar mar aar)
      if (supported_languages.include? project.compile.language || 
          project.packages.detect { |pkg| supported_packaging.include?(pkg.type.to_s) })
        eclipse.enhance [ file(project.path_to(".classpath")), file(project.path_to(".project")) ]

        # The only thing we need to look for is a change in the Buildfile.
        file(project.path_to(".classpath")=>sources) do |task|
          info "Writing #{task.name}"

          # Find a path relative to the project's root directory.
          relative = lambda do |path|
            path or raise "Invalid path '#{path.inspect}'"
            msg = [:to_path, :to_str, :to_s].find { |msg| path.respond_to? msg }
            path = path.__send__(msg)
            Util.relative_path(File.expand_path(path), project.path_to)
          end

          m2repo = Buildr::Repositories.instance.local
          excludes = [ '**/.svn/', '**/CVS/' ].join('|')

          File.open(task.name, "w") do |file|
            xml = Builder::XmlMarkup.new(:target=>file, :indent=>2)
            xml.classpath do
              # Note: Use the test classpath since Eclipse compiles both "main" and "test" classes using the same classpath
              cp = project.test.compile.dependencies.map(&:to_s) - [ project.compile.target.to_s, project.resources.target.to_s ]
              cp = cp.uniq

              # Convert classpath elements into applicable Project objects
              cp.collect! { |path| Buildr.projects.detect { |prj| prj.packages.detect { |pkg| pkg.to_s == path } } || path }

              # project_libs: artifacts created by other projects
              project_libs, others = cp.partition { |path| path.is_a?(Project) }

              # Separate artifacts from Maven2 repository
              m2_libs, others = others.partition { |path| path.to_s.index(m2repo) == 0 }

              # Generated: classpath elements in the project are assumed to be generated
              generated, libs = others.partition { |path| path.to_s.index(project.path_to.to_s) == 0 }

              # Main resources implicitly copied into project.compile.target
              srcs = (project.compile.sources + generated + project.resources.sources).map { |src| relative[src] }

              srcs.sort.uniq.each do |path|
                xml.classpathentry :kind=>'src', :path=>path, :excluding=>excludes
              end

              if project.test.compile.target
                # Test classes are generated in a separate output directory
                test_sources = project.test.compile.sources.map { |src| relative[src] }
                test_sources.each do |paths|
                  paths.sort.uniq.each do |path|
                    xml.classpathentry :kind=>'src', :path=>path, :output => relative[project.test.compile.target], :excluding=>excludes
                  end
                end

                # Test resources go in separate output directory as well
                test_resource_sources = project.test.resources.sources.map { |src| relative[src] }
                test_resource_sources.each do |path|
                  xml.classpathentry :kind=>'src', :path=>path, :output => relative[project.test.compile.target], :excluding=>excludes
                end
              end

              # Classpath elements from other projects
              project_libs.map(&:id).sort.uniq.each do |project_id|
                xml.classpathentry :kind=>'src', :combineaccessrules=>"false", :path=>"/#{project_id}" 
              end

              { :output => relative[project.compile.target],
                :lib    => libs.map(&:to_s),
                :var    => m2_libs.map { |path| path.to_s.sub(m2repo, 'M2_REPO') }
              }.each do |kind, paths|
                paths.sort.uniq.each do |path|
                  xml.classpathentry :kind=>kind, :path=>path
                end
              end

              xml.classpathentry :kind=>'con', :path=>'ch.epfl.lamp.sdt.launching.SCALA_CONTAINER' if scala
              xml.classpathentry :kind=>'con', :path=>'org.eclipse.jdt.launching.JRE_CONTAINER'
            end
          end
        end

        # The only thing we need to look for is a change in the Buildfile.
        file(project.path_to(".project")=>sources) do |task|
          info "Writing #{task.name}"
          File.open(task.name, "w") do |file|
            xml = Builder::XmlMarkup.new(:target=>file, :indent=>2)
            xml.projectDescription do
              xml.name project.id
              xml.projects
              xml.buildSpec do
                if scala
                  xml.buildCommand do
                    xml.name "ch.epfl.lamp.sdt.core.scalabuilder"
                  end
                else
                  xml.buildCommand do
                    xml.name "org.eclipse.jdt.core.javabuilder"
                  end
                end
              end
              xml.natures do
                xml.nature "ch.epfl.lamp.sdt.core.scalanature" if scala
                xml.nature "org.eclipse.jdt.core.javanature"
              end
            end
          end
        end
      end

    end

  end
end # module Buildr


class Buildr::Project
  include Buildr::Eclipse
end
