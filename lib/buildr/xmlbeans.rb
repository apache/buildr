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


require "java/java"
require "java/ant"

module Buildr

  # Provides XMLBeans schema compiler. Require explicitly using <code>require "buildr/xmlbeans"</code>.
  #
  #   require 'buildr/xmlbeans'
  #   define 'some_proj' do 
  #      compile_xml_beans _(:source, :main, :xsd) # the directory with *.xsd
  #   end
  module XMLBeans

    # You can use ArtifactNamespace to customize the versions of 
    # <code>:xmlbeans</code> or <code>:stax</code> used by this module:
    #
    #   require 'buildr/xmlbeans'
    #   artifacts[Buildr::XMLBeans].use :xmlbeans => '2.2.0'
    REQUIRES = ArtifactNamespace.for self, {
      'stax:stax-api:jar:>=1' => '1.0.1',
      'org.apache.xmlbeans:xmlbeans:jar:>2' => '2.3.0'
    }
    
    class << self

      def compile(*args)
        options = Hash === args.last ? args.pop : {}
        options[:verbose] ||= Rake.application.options.trace || false
        rake_check_options options, :verbose, :noop, :javasource, :jar, :compile, :output, :xsb
        puts "Running XMLBeans schema compiler" if verbose
        Buildr.ant "xmlbeans" do |ant|
          ant.taskdef :name=>"xmlbeans", :classname=>"org.apache.xmlbeans.impl.tool.XMLBean",
            :classpath=>requires.map(&:to_s).join(File::PATH_SEPARATOR)
          ant.xmlbeans :srconly=>"true", :srcgendir=>options[:output].to_s, :classgendir=>options[:output].to_s, 
            :javasource=>options[:javasource] do
            args.flatten.each { |file| ant.fileset File.directory?(file) ? { :dir=>file } : { :file=>file } }
          end
        end
        # Touch paths to let other tasks know there's an update.
        touch options[:output].to_s, :verbose=>false
      end

      def requires
        REQUIRES.each { |artifact| artifact.invoke }
      end
    end

    def compile_xml_beans(*args)
      # Run whenever XSD file changes, but typically we're given an directory of XSD files, or even file patterns
      # (the last FileList is there to deal with things like *.xsdconfig).
      files = args.flatten.map { |file| File.directory?(file) ? FileList["#{file}/*.xsd"] : FileList[file] }.flatten
      # Generate sources and add them to the compile task.
      generated = file(path_to(:target, :generated, :xmlbeans)=>files) do |task|
        XMLBeans.compile args.flatten, :output=>task.name,
          :javasource=>compile.options.source, :xsb=>compile.target
      end
      compile.using(:javac).from(generated).with(*XMLBeans.requires)
      # Once compiled, we need to copy the generated XSB/XSD and one (magical?) class file
      # into the target directory, or the rest is useless.
      compile do |task|
        verbose(false) do
          base = Pathname.new(generated.to_s)
          FileList["#{base}/**/*.{class,xsb,xsd}"].each do |file|
            target = File.join(compile.target.to_s, Pathname.new(file).relative_path_from(base))
            mkpath File.dirname(target) ; cp file, target
          end
        end
      end
    end

  end

  class Project
    include XMLBeans
  end
end
