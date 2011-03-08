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
require 'stringio'


module Buildr
  module IntellijIdea
    # Abstract base class for IdeaModule and IdeaProject
    class IdeaFile
      DEFAULT_SUFFIX = ""

      attr_reader :buildr_project
      attr_writer :suffix
      attr_writer :id
      attr_accessor :template

      def suffix
        @suffix ||= DEFAULT_SUFFIX
      end

      def filename
        buildr_project.path_to("#{name}.#{extension}")
      end

      def id
        @id ||= buildr_project.name.split(':').last
      end

      def add_component(name, attrs = {}, &xml)
        self.components << create_component(name, attrs, &xml)
      end

      def write(f)
        document.write f
      end

      protected

      def name
        "#{self.id}#{suffix}"
      end

      def create_component(name, attrs = {})
        target = StringIO.new
        Builder::XmlMarkup.new(:target => target, :indent => 2).component(attrs.merge({:name => name})) do |xml|
          yield xml if block_given?
        end
        REXML::Document.new(target.string).root
      end

      def components
        @components ||= self.default_components.compact
      end

      def load_document(filename)
        REXML::Document.new(File.read(filename))
      end

      def document
        if File.exist?(self.filename)
          doc = load_document(self.filename)
        else
          doc = base_document
          inject_components(doc, self.initial_components)
        end
        if self.template
          template_doc = load_document(self.template)
          REXML::XPath.each(template_doc, "//component") do |element|
            inject_component(doc, element)
          end
        end
        inject_components(doc, self.components)
        doc
      end

      def inject_components(doc, components)
        components.each do |component|
          # execute deferred components
          component = component.call if Proc === component
          inject_component(doc, component) if component
        end
      end

      # replace overridden component (if any) with specified component
      def inject_component(doc, component)
        doc.root.delete_element("//component[@name='#{component.attributes['name']}']")
        doc.root.add_element component
      end
    end

    # IdeaModule represents an .iml file
    class IdeaModule < IdeaFile
      DEFAULT_TYPE = "JAVA_MODULE"
      DEFAULT_LOCAL_REPOSITORY_ENV_OVERRIDE = "MAVEN_REPOSITORY"

      attr_accessor :type
      attr_accessor :local_repository_env_override
      attr_accessor :group
      attr_reader :facets

      def initialize
        @type = DEFAULT_TYPE
        @local_repository_env_override = DEFAULT_LOCAL_REPOSITORY_ENV_OVERRIDE
      end

      def buildr_project=(buildr_project)
        @id = nil
        @facets = []
        @skip_content = false
        @buildr_project = buildr_project
      end

      def extension
        "iml"
      end

      def main_source_directories
        @main_source_directories ||= [
          buildr_project.compile.sources,
          buildr_project.resources.sources
        ].flatten.compact
      end

      def test_source_directories
        @test_source_directories ||= [
          buildr_project.test.compile.sources,
          buildr_project.test.resources.sources
        ].flatten.compact
      end

      def excluded_directories
        @excluded_directories ||= [
          buildr_project.resources.target,
          buildr_project.test.resources.target,
          buildr_project.path_to(:target, :main),
          buildr_project.path_to(:target, :test),
          buildr_project.path_to(:reports)
        ].flatten.compact
      end

      attr_writer :main_output_dir

      def main_output_dir
        @main_output_dir ||= buildr_project._(:target, :main, :java)
      end

      attr_writer :test_output_dir

      def test_output_dir
        @test_output_dir ||= buildr_project._(:target, :test, :java)
      end

      def main_dependencies
        @main_dependencies ||=  buildr_project.compile.dependencies
      end

      def test_dependencies
        @test_dependencies ||=  buildr_project.test.compile.dependencies
      end

      def add_facet(name, type)
        target = StringIO.new
        Builder::XmlMarkup.new(:target => target, :indent => 2).facet(:name => name, :type => type) do |xml|
          yield xml if block_given?
        end
        self.facets << REXML::Document.new(target.string).root
      end

      def skip_content?
        !!@skip_content
      end

      def skip_content!
        @skip_content = true
      end

      protected

      def test_dependency_details
        main_dependencies_paths = main_dependencies.map(&:to_s)
        target_dir = buildr_project.compile.target.to_s
        test_dependencies.select { |d| d.to_s != target_dir }.collect do |d|
          dependency_path = d.to_s
          export = main_dependencies_paths.include?(dependency_path)
          source_path = nil
          if d.respond_to?(:to_spec_hash)
            source_spec = d.to_spec_hash.merge(:classifier => 'sources')
            source_path = Buildr.artifact(source_spec).to_s
            source_path = nil unless File.exist?(source_path)
          end
          [dependency_path, export, source_path]
        end

      end

      def base_directory
        buildr_project.path_to
      end

      def base_document
        target = StringIO.new
        Builder::XmlMarkup.new(:target => target).module(:version => "4", :relativePaths => "true", :type => self.type)
        REXML::Document.new(target.string)
      end

      def initial_components
        []
      end

      def default_components
        [
          lambda { module_root_component },
          lambda { facet_component }
        ]
      end

      def facet_component
        return nil if self.facets.empty?
        fm = self.create_component("FacetManager")
        self.facets.each do |facet|
          fm.add_element facet
        end
        fm
      end

      def module_root_component
        create_component("NewModuleRootManager", "inherit-compiler-output" => "false") do |xml|
          generate_compile_output(xml)
          generate_content(xml) unless skip_content?
          generate_initial_order_entries(xml)
          project_dependencies = []

          # Note: Use the test classpath since IDEA compiles both "main" and "test" classes using the same classpath
          self.test_dependency_details.each do |dependency_path, export, source_path|
            project_for_dependency = Buildr.projects.detect do |project|
              [project.packages, project.compile.target, project.resources.target, project.test.compile.target, project.test.resources.target].flatten.
                detect { |proj_art| proj_art.to_s == dependency_path }
            end
            if project_for_dependency
              if project_for_dependency.iml? && !project_dependencies.include?(project_for_dependency)
                generate_project_dependency(xml, project_for_dependency.iml.name, export)
              end
              project_dependencies << project_for_dependency
              next
            else
              generate_module_lib(xml, url_for_path(dependency_path), export, (source_path ? url_for_path(source_path) : nil))
            end
          end

          xml.orderEntryProperties
        end
      end

      def jar_path(path)
        "jar://#{resolve_path(path)}!/"
      end

      def file_path(path)
        "file://#{resolve_path(path)}"
      end

      def url_for_path(path)
        if path =~ /jar$/i
          jar_path(path)
        else
          file_path(path)
        end
      end

      def resolve_path(path)
        m2repo = Buildr::Repositories.instance.local
        if path.to_s.index(m2repo) == 0 && !self.local_repository_env_override.nil?
          return path.sub(m2repo, "$#{self.local_repository_env_override}$")
        else
          begin
            return "$MODULE_DIR$/#{relative(path)}"
          rescue ArgumentError
            # ArgumentError happens on windows when self.base_directory and path are on different drives
            return path
          end
        end
      end

      def relative(path)
        ::Buildr::Util.relative_path(File.expand_path(path.to_s), self.base_directory)
      end

      def generate_compile_output(xml)
        xml.output(:url => file_path(self.main_output_dir.to_s))
        xml.tag!("output-test", :url => file_path(self.test_output_dir.to_s))
        xml.tag!("exclude-output")
      end

      def generate_content(xml)
        xml.content(:url => "file://$MODULE_DIR$") do
          # Source folders
          {
            :main => self.main_source_directories,
            :test => self.test_source_directories
          }.each do |kind, directories|
            directories.map { |dir| dir.to_s }.compact.sort.uniq.each do |dir|
              xml.sourceFolder :url => file_path(dir), :isTestSource => (kind == :test ? 'true' : 'false')
            end
          end

          # Exclude target directories
          self.net_excluded_directories.
            collect { |dir| file_path(dir) }.
            select { |dir| relative_dir_inside_dir?(dir) }.
            sort.each do |dir|
            xml.excludeFolder :url => dir
          end
        end
      end

      def relative_dir_inside_dir?(dir)
        !dir.include?("../")
      end

      def generate_initial_order_entries(xml)
        xml.orderEntry :type => "sourceFolder", :forTests => "false"
        xml.orderEntry :type => "inheritedJdk"
      end

      def generate_project_dependency(xml, other_project, export = true)
        attribs = {:type => 'module', "module-name" => other_project}
        attribs[:exported] = '' if export
        xml.orderEntry attribs
      end

      def generate_module_lib(xml, path, export, source_path)
        attribs = {:type => 'module-library'}
        attribs[:exported] = '' if export
        xml.orderEntry attribs do
          xml.library do
            xml.CLASSES do
              xml.root :url => path
            end
            xml.JAVADOC
            xml.SOURCES do
              if source_path
                xml.root :url => source_path
              end
            end
          end
        end
      end

      # Don't exclude things that are subdirectories of other excluded things
      def net_excluded_directories
        net = []
        all = self.excluded_directories.map { |dir| buildr_project._(dir.to_s) }.sort_by { |d| d.size }
        all.each_with_index do |dir, i|
          unless all[0 ... i].find { |other| dir =~ /^#{other}/ }
            net << dir
          end
        end
        net
      end
    end

    # IdeaModule represents an .ipr file
    class IdeaProject < IdeaFile
      attr_accessor :vcs
      attr_accessor :extra_modules
      attr_writer :jdk_version

      def initialize(buildr_project)
        @buildr_project = buildr_project
        @vcs = detect_vcs
        @extra_modules = []
      end

      def jdk_version
        @jdk_version ||= buildr_project.compile.options.source || "1.6"
      end

      protected

      def extension
        "ipr"
      end

      def detect_vcs
        if File.directory?(buildr_project._('.svn'))
          "svn"
        elsif File.directory?(buildr_project._('.git'))
          "Git"
        end
      end

      def base_document
        target = StringIO.new
        Builder::XmlMarkup.new(:target => target).project(:version => "4", :relativePaths => "false")
        REXML::Document.new(target.string)
      end

      def default_components
        [
          lambda { modules_component },
          vcs_component
        ]
      end

      def initial_components
        [
          lambda { project_root_manager_component },
          lambda { project_details_component }
        ]
      end

      def project_root_manager_component
        attribs = {"version" => "2",
                   "assert-keyword" => "true",
                   "jdk-15" => "true",
                   "project-jdk-name" => self.jdk_version,
                   "project-jdk-type" => "JavaSDK",
                   "languageLevel" => "JDK_#{self.jdk_version.gsub('.', '_')}"}
        create_component("ProjectRootManager", attribs) do |xml|
          xml.output("url" => "file://$PROJECT_DIR$/out")
        end
      end

      def project_details_component
        create_component("ProjectDetails") do |xml|
          xml.option("name" => "projectName", "value" => self.name)
        end
      end

      def modules_component
        create_component("ProjectModuleManager") do |xml|
          xml.modules do
            buildr_project.projects.select { |subp| subp.iml? }.each do |subproject|
              module_path = subproject.base_dir.gsub(/^#{buildr_project.base_dir}\//, '')
              path = "#{module_path}/#{subproject.iml.name}.iml"
              attribs = {:fileurl => "file://$PROJECT_DIR$/#{path}", :filepath => "$PROJECT_DIR$/#{path}"}
              if subproject.iml.group == true
                attribs[:group] = subproject.parent.name.gsub(':', '/')
              elsif !subproject.iml.group.nil?
                attribs[:group] = subproject.group.to_s
              end
              xml.module attribs
            end
            self.extra_modules.each do |iml_file|
              xml.module :fileurl => "file://$PROJECT_DIR$/#{iml_file}",
                         :filepath => "$PROJECT_DIR$/#{iml_file}"
            end
            if buildr_project.iml?
              xml.module :fileurl => "file://$PROJECT_DIR$/#{buildr_project.iml.name}.iml",
                         :filepath => "$PROJECT_DIR$/#{buildr_project.iml.name}.iml"
            end
          end
        end
      end

      def vcs_component
        if vcs
          create_component("VcsDirectoryMappings") do |xml|
            xml.mapping :directory => "", :vcs => vcs
          end
        end
      end
    end

    module ProjectExtension
      include Extension

      first_time do
        desc "Generate Intellij IDEA artifacts for all projects"
        Project.local_task "idea:generate" => "artifacts"

        desc "Delete the generated Intellij IDEA artifacts"
        Project.local_task "idea:clean"
      end

      before_define do |project|
        project.recursive_task("idea:generate")
        project.recursive_task("idea:clean")
      end

      after_define do |project|
        idea = project.task("idea:generate")

        files = [
          (project.iml if project.iml?),
          (project.ipr if project.ipr?)
        ].compact

        files.each do |ideafile|
          module_dir =  File.dirname(ideafile.filename)
          # Need to clear the actions else the extension included as part of buildr will run
          file(ideafile.filename).clear_actions
          idea.enhance [file(ideafile.filename)]
          file(ideafile.filename => [Buildr.application.buildfile]) do |task|
            mkdir_p module_dir
            info "Writing #{task.name}"
            t = Tempfile.open("buildr-idea")
            temp_filename = t.path
            t.close!
            File.open(temp_filename, "w") do |f|
              ideafile.write f
            end
            mv temp_filename, ideafile.filename
          end
        end

        project.task("idea:clean") do
          files.each do |f|
            info "Removing #{f.filename}" if File.exist?(f.filename)
            rm_rf f.filename
          end
        end
      end

      def ipr
        if ipr?
          @ipr ||= IdeaProject.new(self)
        else
          raise "Only the root project has an IPR"
        end
      end

      def ipr?
        !@no_ipr && self.parent.nil?
      end

      def iml
        if iml?
          unless @iml
            inheritable_iml_source = self.parent
            while inheritable_iml_source && !inheritable_iml_source.iml?
              inheritable_iml_source = inheritable_iml_source.parent;
            end
            @iml = inheritable_iml_source ? inheritable_iml_source.iml.clone : IdeaModule.new
            @iml.buildr_project = self
          end
          return @iml
        else
          raise "IML generation is disabled for #{self.name}"
        end
      end

      def no_ipr
        @no_ipr = true
      end

      def no_iml
        @has_iml = false
      end

      def iml?
        @has_iml = @has_iml.nil? ? true : @has_iml
      end
    end
  end
end

class Buildr::Project
  include Buildr::IntellijIdea::ProjectExtension
end
