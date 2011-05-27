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

require 'buildr/core/doc'
require 'buildr/scala/compiler'   # ensure Scala dependencies are ready

module Buildr
  module Doc

    module ScaladocDefaults
      include Extension

      # Default scaladoc -doc-title to project's comment or name
      after_define(:scaladoc => :doc) do |project|
        if project.doc.engine? Scaladoc
          options = project.doc.options
          key = Scala.version?(2.7) ? :windowtitle : "doc-title".to_sym
          options[key] = (project.comment || project.name) unless options[key]
        end
      end
    end

    class Scaladoc < Base
      specify :language => :scala, :source_ext => 'scala'

      def generate(sources, target, options = {})
        cmd_args = [ '-d', target, trace?(:scaladoc) ? '-verbose' : '' ]
        options.reject { |key, value| [:sourcepath, :classpath].include?(key) }.
          each { |key, value| value.invoke if value.respond_to?(:invoke) }.
          each do |key, value|
            case value
            when true, nil
              cmd_args << "-#{key}"
            when false
              cmd_args << "-no#{key}"
            when Hash
              value.each { |k,v| cmd_args << "-#{key}" << k.to_s << v.to_s }
            else
              cmd_args += Array(value).map { |item| ["-#{key}", item.to_s] }.flatten
            end
          end
        [:sourcepath, :classpath].each do |option|
          Array(options[option]).flatten.tap do |paths|
            cmd_args << "-#{option}" << paths.flatten.map(&:to_s).join(File::PATH_SEPARATOR) unless paths.empty?
          end
        end
        cmd_args += sources.flatten.uniq
        unless Buildr.application.options.dryrun
          info "Generating Scaladoc for #{project.name}"
          trace (['scaladoc'] + cmd_args).join(' ')
          Java.load
          begin
            Java.scala.tools.nsc.ScalaDoc.process(cmd_args.to_java(Java.java.lang.String))
          rescue => e
            fail 'Failed to generate Scaladocs, see errors above: ' + e
          end
        end
      end
    end

    class VScaladoc < Base
      VERSION = '1.2-m1'
      Buildr.repositories.remote << 'http://scala-tools.org/repo-snapshots'

      class << self
        def dependencies
          [ "org.scala-tools:vscaladoc:jar:#{VERSION}" ]
        end
      end

      Java.classpath << dependencies

      specify :language => :scala, :source_ext => 'scala'

      def generate(sources, target, options = {})
        cmd_args = [ '-d', target, (trace?(:vscaladoc) ? '-verbose' : ''),
          '-sourcepath', project.compile.sources.join(File::PATH_SEPARATOR) ]
        options.reject { |key, value| [:sourcepath, :classpath].include?(key) }.
          each { |key, value| value.invoke if value.respond_to?(:invoke) }.
          each do |key, value|
            case value
            when true, nil
              cmd_args << "-#{key}"
            when false
              cmd_args << "-no#{key}"
            when Hash
              value.each { |k,v| cmd_args << "-#{key}" << k.to_s << v.to_s }
            else
              cmd_args += Array(value).map { |item| ["-#{key}", item.to_s] }.flatten
            end
          end
        [:sourcepath, :classpath].each do |option|
          Array(options[option]).flatten.tap do |paths|
            cmd_args << "-#{option}" << paths.flatten.map(&:to_s).join(File::PATH_SEPARATOR) unless paths.empty?
          end
        end
        cmd_args += sources.flatten.uniq
        unless Buildr.application.options.dryrun
          info "Generating VScaladoc for #{project.name}"
          trace (['vscaladoc'] + cmd_args).join(' ')
          Java.load
          Java.org.scala_tools.vscaladoc.Main.main(cmd_args.to_java(Java.java.lang.String)) == 0 or
            fail 'Failed to generate VScaladocs, see errors above'
        end
      end
    end
  end

  module Packaging
    module Scala
      def package_as_scaladoc_spec(spec) #:nodoc:
        spec.merge(:type=>:jar, :classifier=>'scaladoc')
      end

      def package_as_scaladoc(file_name) #:nodoc:
        ZipTask.define_task(file_name).tap do |zip|
          zip.include :from=>doc.target
        end
      end
    end
  end

  class Project
    include ScaladocDefaults
    include Packaging::Scala
  end
end

Buildr::Doc.engines << Buildr::Doc::Scaladoc
Buildr::Doc.engines << Buildr::Doc::VScaladoc
