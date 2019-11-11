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
  # Provides the <code>spotbugs:html</code> and <code>spotbugs:xml</code> tasks.
  # Require explicitly using <code>require "buildr/spotbugs"</code>.
  module Spotbugs

    class << self

      # The specs for requirements
      def dependencies
        %w(
          com.google.code.findbugs:jsr305:jar:3.0.2
          com.github.spotbugs:spotbugs-ant:jar:3.1.5
          com.github.spotbugs:spotbugs:jar:3.1.5
          com.github.spotbugs:spotbugs-annotations:jar:3.1.5
          com.google.code.findbugs:jFormatString:jar:3.0.0
          commons-lang:commons-lang:jar:2.6
          org.dom4j:dom4j:jar:2.1.0
          jaxen:jaxen:jar:1.1.6
          net.jcip:jcip-annotations:jar:1.0
          org.apache.bcel:bcel:jar:6.2

          org.ow2.asm:asm:jar:7.1
          org.ow2.asm:asm-analysis:jar:7.1
          org.ow2.asm:asm-commons:jar:7.1
          org.ow2.asm:asm-tree:jar:7.1
          org.ow2.asm:asm-util:jar:7.1
        )
      end

      def fb_contrib_dependencies
        %w(com.mebigfatguy.fb-contrib:fb-contrib:jar:7.4.2.sb)
      end

      def spotbugs(output_file, source_paths, analyze_paths, options = {})
        dependencies = (options[:dependencies] || []) + self.dependencies
        cp = Buildr.artifacts(dependencies).each { |a| a.invoke if a.respond_to?(:invoke) }.map(&:to_s).join(File::PATH_SEPARATOR)

        plugins = (options[:plugins] || self.fb_contrib_dependencies)
        pluginList = Buildr.artifacts(plugins).each { |a| a.invoke if a.respond_to?(:invoke) }.map(&:to_s).join(File::PATH_SEPARATOR)

        args = {
            :output => options[:output] || 'xml',
            :outputFile => output_file,
            :effort => 'max',
            :pluginList => pluginList,
            :classpath => cp,
            :reportLevel => options[:report_level] || 'low',
            :timeout => '90000000',
            :debug => 'false'
        }
        args[:failOnError] = true if options[:fail_on_error]
        args[:excludeFilter] = options[:exclude_filter] if options[:exclude_filter]
        args[:jvmargs] = options[:java_args] if options[:java_args]

        mkdir_p File.dirname(output_file)

        Buildr.ant('spotbugs') do |ant|
          ant.taskdef :name => 'spotbugs',
                      :classname => 'edu.umd.cs.findbugs.anttask.FindBugsTask',
                      :classpath => cp
          ant.spotbugs args do
            source_paths.each do |source_path|
              ant.sourcePath :path => source_path.to_s
            end
            Buildr.artifacts(analyze_paths).each(&:invoke).each do |analyze_path|
              ant.auxAnalyzePath :path => analyze_path.to_s
            end
            if options[:properties]
              options[:properties].each_pair do |k, v|
                ant.systemProperty :name => k, :value => v
              end
            end
            if options[:extra_dependencies]
              ant.auxClasspath do |aux|
                Buildr.artifacts(options[:extra_dependencies]).each { |a| a.invoke if a.respond_to?(:invoke) }.each do |dep|
                  aux.pathelement :location => dep.to_s
                end
              end
            end
          end
        end
      end
    end

    class Config

      attr_accessor :enabled

      def enabled?
        !!@enabled
      end

      attr_writer :config_directory

      def config_directory
        @config_directory || project._(:source, :main, :etc, :spotbugs)
      end

      attr_writer :report_level

      def report_level
        @report_level || 'medium'
      end

      attr_writer :report_dir

      def report_dir
        @report_dir || project._(:reports, :spotbugs)
      end

      attr_writer :fail_on_error

      def fail_on_error?
        @fail_on_error.nil? ? false : @fail_on_error
      end

      attr_writer :xml_output_file

      def xml_output_file
        @xml_output_file || "#{self.report_dir}/spotbugs.xml"
      end

      attr_writer :html_output_file

      def html_output_file
        @html_output_file || "#{self.report_dir}/spotbugs.html"
      end

      attr_writer :filter_file

      def filter_file
        @filter_file || "#{self.config_directory}/filter.xml"
      end

      def properties
        @properties ||= {}
      end

      attr_writer :java_args

      def java_args
        @java_args || '-server -Xss1m -Xmx800m -Duser.language=en -Duser.region=EN '
      end

      def source_paths
        @source_paths ||= [self.project.compile.sources, self.project.test.compile.sources].flatten.compact
      end

      def analyze_paths
        @analyze_path ||= [self.project.compile.target]
      end

      def extra_dependencies
        @extra_dependencies ||= [self.project.compile.dependencies, self.project.test.compile.dependencies].flatten.compact
      end

      # An array of additional projects to scan for main and test sources
      attr_writer :additional_project_names

      def additional_project_names
        @additional_project_names ||= []
      end

      def complete_source_paths
        paths = self.source_paths.dup

        self.additional_project_names.each do |project_name|
          p = self.project.project(project_name)
          paths << [p.compile.sources, p.test.compile.sources].flatten.compact
        end

        paths.flatten.compact
      end

      def complete_analyze_paths
        paths = self.analyze_paths.dup

        self.additional_project_names.each do |project_name|
          paths << self.project.project(project_name).compile.target
        end

        paths.flatten.compact
      end

      def complete_extra_dependencies
        deps = self.extra_dependencies.dup

        self.additional_project_names.each do |project_name|
          p = self.project.project(project_name)
          deps << [p.compile.dependencies, p.test.compile.dependencies].flatten.compact
        end

        deps.flatten.compact
      end


      protected

      def initialize(project)
        @project = project
      end

      attr_reader :project
    end

    module ProjectExtension
      include Extension

      def spotbugs
        @spotbugs ||= Buildr::Spotbugs::Config.new(project)
      end

      after_define do |project|
        if project.spotbugs.enabled?
          desc 'Generate spotbugs xml report.'
          project.task('spotbugs:xml') do
            puts 'Spotbugs: Analyzing source code...'
            options =
                {
                    :properties => project.spotbugs.properties,
                    :fail_on_error => project.spotbugs.fail_on_error?,
                    :extra_dependencies => project.spotbugs.complete_extra_dependencies
                }
            options[:exclude_filter] = project.spotbugs.filter_file if File.exist?(project.spotbugs.filter_file)
            options[:output] = 'xml:withMessages'
            options[:report_level] = project.spotbugs.report_level

            Buildr::Spotbugs.spotbugs(project.spotbugs.xml_output_file,
                                      project.spotbugs.complete_source_paths,
                                      project.spotbugs.complete_analyze_paths,
                                      options)
          end

          desc 'Generate spotbugs html report.'
          project.task('spotbugs:html') do
            puts 'Spotbugs: Analyzing source code...'
            options =
                {
                    :properties => project.spotbugs.properties,
                    :fail_on_error => project.spotbugs.fail_on_error?,
                    :extra_dependencies => project.spotbugs.complete_extra_dependencies
                }
            options[:exclude_filter] = project.spotbugs.filter_file if File.exist?(project.spotbugs.filter_file)
            options[:output] = 'html'
            options[:report_level] = project.spotbugs.report_level

            Buildr::Spotbugs.spotbugs(project.spotbugs.html_output_file,
                                      project.spotbugs.complete_source_paths,
                                      project.spotbugs.complete_analyze_paths,
                                      options)
          end
        end
      end
    end
  end
end

class Buildr::Project
  include Buildr::Spotbugs::ProjectExtension
end
