require 'core/package'
require 'java/java'
require 'tasks/zip'
require 'tasks/tar'


module Buildr
  module Java

    # Adds packaging for Java projects: JAR, WAR, AAR, EAR, Javadoc.
    module Packaging

      # Adds support for MANIFEST.MF and other META-INF files.
      module WithManifest #:nodoc:

        def self.included(base)
          base.send :alias_method_chain, :initialize, :manifest
        end

        MANIFEST_HEADER = ['Manifest-Version: 1.0', 'Created-By: Buildr']

        # Specifies how to create the manifest file.
        attr_accessor :manifest

        # Specifies files to include in the META-INF directory.
        attr_accessor :meta_inf

        def initialize_with_manifest(*args) #:nodoc:
          initialize_without_manifest *args
          @manifest = false
          @meta_inf = []

          prepare do
            @prerequisites << manifest if String === manifest || Rake::Task === manifest
            [meta_inf].flatten.map { |file| file.to_s }.uniq.each { |file| path('META-INF').include file }
          end

          enhance do
            if manifest
              # Tempfiles gets deleted on garbage collection, so we're going to hold on to it
              # through instance variable not closure variable.
              Tempfile.open 'MANIFEST.MF' do |@manifest_tmp|
                lines = String === manifest || Rake::Task === manifest ? manifest_lines_from(File.read(manifest.to_s)) :
                  manifest_lines_from(manifest)
                @manifest_tmp.write((MANIFEST_HEADER + lines).join("\n"))
                @manifest_tmp.write "\n"
                path('META-INF').include @manifest_tmp.path, :as=>'MANIFEST.MF'
              end
            end
          end
        end

      private

        def manifest_lines_from(arg)
          case arg
          when Hash
            arg.map { |name, value| "#{name}: #{value}" }.sort.
              map { |line| manifest_wrap_at_72(line) }.flatten
          when Array
            arg.map { |section|
              name = section.has_key?('Name') ? ["Name: #{section['Name']}"] : []
              name + section.except('Name').map { |name, value| "#{name}: #{value}" }.sort + ['']
            }.flatten.map { |line| manifest_wrap_at_72(line) }.flatten
          when Proc, Method
            manifest_lines_from(arg.call)
          when String
            arg.split("\n").map { |line| manifest_wrap_at_72(line) }.flatten
          else
            fail 'Invalid manifest, expecting Hash, Array, file name/task or proc/method.'
          end
        end

        def manifest_wrap_at_72(arg)
          #return arg.map { |line| manifest_wrap_at_72(line) }.flatten.join("\n") if Array === arg
          return arg if arg.size < 72
          [ arg[0..70], manifest_wrap_at_72(' ' + arg[71..-1]) ]
        end

      end

      class ::Buildr::ZipTask
        include WithManifest
      end


      # Extends the ZipTask to create a JAR file.
      #
      # This task supports two additional attributes: manifest and meta-inf.
      #
      # The manifest attribute specifies how to create the MANIFEST.MF file.
      # * A hash of manifest properties (name/value pairs).
      # * An array of hashes, one for each section of the manifest.
      # * A string providing the name of an existing manifest file.
      # * A file task can be used the same way.
      # * Proc or method called to return the contents of the manifest file.
      # * False to not generate a manifest file.
      #
      # The meta-inf attribute lists one or more files that should be copied into
      # the META-INF directory.
      #
      # For example:
      #   package(:jar).with(:manifest=>'src/MANIFEST.MF')
      #   package(:jar).meta_inf << file('README')
      class JarTask < ZipTask

        def initialize(*args) #:nodoc:
          super
        end

        # :call-seq:
        #   with(options) => self
        #
        # Additional 
        # Pass options to the task. Returns self. ZipTask itself does not support any options,
        # but other tasks (e.g. JarTask, WarTask) do.
        #
        # For example:
        #   package(:jar).with(:manifest=>'MANIFEST_MF')
        def with(*args)
          super args.pop if Hash === args.last
          include :from=>args
          self
        end

      end

      # Extends the JarTask to create a WAR file.
      #
      # Supports all the same options as JarTask, in additon to these two options:
      # * :libs -- An array of files, tasks, artifact specifications, etc that will be added
      #   to the WEB-INF/lib directory.
      # * :classes -- A directory containing class files for inclusion in the WEB-INF/classes
      #   directory.
      #
      # For example:
      #   package(:war).with(:libs=>'log4j:log4j:jar:1.1')
      class WarTask < JarTask

        # Directories with class files to include under WEB-INF/classes.
        attr_accessor :classes

        # Artifacts to include under WEB-INF/libs.
        attr_accessor :libs

        def initialize(*args) #:nodoc:
          super
          @classes = []
          @libs = []
          prepare do
            @classes.to_a.flatten.each { |classes| path('WEB-INF/classes').include classes, :as=>'.' }
            path('WEB-INF/lib').include Buildr.artifacts(@libs) unless @libs.nil? || @libs.empty?
          end
        end

        def libs=(value) #:nodoc:
          @libs = Buildr.artifacts(value)
        end

        def classes=(value) #:nodoc:
          @classes = [value].flatten.map { |dir| file(dir.to_s) }
        end
  
      end

      # Extends the JarTask to create an AAR file (Axis2 service archive).
      #
      # Supports all the same options as JarTask, with the addition of :wsdls, :services_xml and :libs.
      #
      # * :wsdls -- WSDL files to include (under META-INF).  By default packaging will include all WSDL
      #   files found under src/main/axis2.
      # * :services_xml -- Location of services.xml file (included under META-INF).  By default packaging
      #   takes this from src/main/axis2/services.xml.  Use a different path if you genereate the services.xml
      #   file as part of the build.
      # * :libs -- Array of files, tasks, artifact specifications, etc that will be added to the /lib directory.
      #
      # For example:
      #   package(:aar).with(:libs=>'log4j:log4j:jar:1.1')
      #
      #   filter.from('src/main/axis2').into('target').include('services.xml', '*.wsdl').using('http_port'=>'8080')
      #   package(:aar).wsdls.clear
      #   package(:aar).with(:services_xml=>_('target/services.xml'), :wsdls=>_('target/*.wsdl'))
      class AarTask < JarTask
        # Artifacts to include under /lib.
        attr_accessor :libs
        # WSDLs to include under META-INF (defaults to all WSDLs under src/main/axis2).
        attr_accessor :wsdls
        # Location of services.xml file (defaults to src/main/axis2/services.xml).
        attr_accessor :services_xml

        def initialize(*args) #:nodoc:
          super
          @libs = []
          @wsdls = []
          prepare do
            path('META-INF').include @wsdls
            path('META-INF').include @services_xml, :as=>['services.xml'] if @services_xml
            path('lib').include Buildr.artifacts(@libs) unless @libs.nil? || @libs.empty?
          end
        end

        def libs=(value) #:nodoc:
          @libs = Buildr.artifacts(value)
        end

        def wsdls=(value) #:nodoc:
          @wsdls |= Array(value)
        end
      end


      include Extension

      before_define do |project|
        project.manifest ||= project.parent && project.parent.manifest ||
          { 'Build-By'=>ENV['USER'], 'Build-Jdk'=>Java.version,
            'Implementation-Title'=>project.comment || project.name,
            'Implementation-Version'=>project.version }
        project.meta_inf ||= project.parent && project.parent.meta_inf ||
          [project.file('LICENSE')].select { |file| File.exist?(file.to_s) }
      end


      # Manifest used for packaging. Inherited from parent project. The default value is a hash that includes
      # the Build-By, Build-Jdk, Implementation-Title and Implementation-Version values.
      # The later are taken from the project's comment (or name) and version number.
      attr_accessor :manifest

      # Files to always include in the package META-INF directory. The default value include
      # the LICENSE file if one exists in the project's base directory.
      attr_accessor :meta_inf

      # :call-seq:
      #   package_with_sources(options?)
      #
      # Call this when you want the project (and all its sub-projects) to create a source distribution.
      # You can use the source distribution in an IDE when debugging.
      #
      # A source distribution is a ZIP package with the classifier 'sources', which includes all the
      # sources used by the compile task.
      #
      # Packages use the project's manifest and meta_inf properties, which you can override by passing
      # different values (e.g. false to exclude the manifest) in the options.
      #
      # To create source distributions only for specific projects, use the :only and :except options,
      # for example:
      #   package_with_sources :only=>['foo:bar', 'foo:baz']
      #
      # (Same as calling package :sources on each project/sub-project that has source directories.)
      def package_with_sources(options = nil)
        options ||= {}
        enhance do
          selected = options[:only] ? projects(options[:only]) :
            options[:except] ? ([self] + projects - projects(options[:except])) :
            [self] + projects
          selected.reject { |project| project.compile.sources.empty? }.
            each { |project| project.package(:sources) }
        end
      end

      # :call-seq:
      #   package_with_javadoc(options?)
      #
      # Call this when you want the project (and all its sub-projects) to create a JavaDoc distribution.
      # You can use the JavaDoc distribution in an IDE when coding against the API.
      #
      # A JavaDoc distribution is a ZIP package with the classifier 'javadoc', which includes all the
      # sources used by the compile task.
      #
      # Packages use the project's manifest and meta_inf properties, which you can override by passing
      # different values (e.g. false to exclude the manifest) in the options.
      #
      # To create JavaDoc distributions only for specific projects, use the :only and :except options,
      # for example:
      #   package_with_javadoc :only=>['foo:bar', 'foo:baz']
      #
      # (Same as calling package :javadoc on each project/sub-project that has source directories.)
      def package_with_javadoc(options = nil)
        options ||= {}
        enhance do
          selected = options[:only] ? projects(options[:only]) :
            options[:except] ? ([self] + projects - projects(options[:except])) :
            [self] + projects
          selected.reject { |project| project.compile.sources.empty? }.
            each { |project| project.package(:javadoc) }
        end
      end

    protected

      def package_as_jar(file_name) #:nodoc:
        Java::Packaging::JarTask.define_task(file_name).tap do |jar|
          jar.with :manifest=>manifest, :meta_inf=>meta_inf
          jar.with compile.target unless compile.sources.empty?
          jar.with resources.target unless resources.sources.empty?
        end
      end

      def package_as_war(file_name) #:nodoc:
        Java::Packaging::WarTask.define_task(file_name).tap do |war|
          war.with :manifest=>manifest, :meta_inf=>meta_inf
          # Add libraries in WEB-INF lib, and classes in WEB-INF classes
          classes = []
          classes << compile.target unless compile.sources.empty?
          classes << resources.target unless resources.sources.empty?
          war.with :classes=>classes
          war.with :libs=>compile.dependencies
          # Add included files, or the webapp directory.
          webapp = path_to(:source, :main, :webapp)
          war.with webapp if File.exist?(webapp)
        end
      end

      def package_as_aar(file_name) #:nodoc:
        Java::Packaging::AarTask.define_task(file_name).tap do |aar|
          aar.with :manifest=>manifest, :meta_inf=>meta_inf
          aar.with :wsdls=>path_to(:source, :main, :axis2, '*.wsdl')
          aar.with :services_xml=>path_to(:source, :main, :axis2, 'services.xml') 
          aar.with compile.target unless compile.sources.empty?
          aar.with resources.target unless resources.sources.empty?
          aar.with :libs=>compile.dependencies
        end
      end

      def package_as_javadoc_spec(spec) #:nodoc:
        spec.merge(:type=>:zip, :classifier=>'javadoc')
      end

      def package_as_javadoc(file_name) #:nodoc:
        ZipTask.define_task(file_name).tap do |zip|
          zip.include :from=>javadoc.target
          javadoc.options[:windowtitle] ||= project.comment || project.name
        end
      end

    end

  end
end


class Buildr::Project
  include Buildr::Java::Packaging
end
