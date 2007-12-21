require "core/project"
require "java/artifact"
require "java/java"
require "java/compile"
require "java/test"
require "tasks/zip"
require "tasks/tar"


module Buildr
  module Java

    # Methods added to Project to support packaging.
    module Packaging

      # Adds support for MANIFEST.MF and other META-INF files.
      module WithManifest #:nodoc:

        def self.included(base)
          base.alias_method_chain :initialize, :manifest
        end

        MANIFEST_HEADER = ["Manifest-Version: 1.0", "Created-By: Buildr"]

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
            [meta_inf].flatten.map { |file| file.to_s }.uniq.each { |file| path("META-INF").include file }
          end

          enhance do
            if manifest
              # Tempfiles gets deleted on garbage collection, so we're going to hold on to it
              # through instance variable not closure variable.
              Tempfile.open "MANIFEST.MF" do |@manifest_tmp|
                lines = String === manifest || Rake::Task === manifest ? manifest_lines_from(File.read(manifest.to_s)) :
                  manifest_lines_from(manifest)
                @manifest_tmp.write((MANIFEST_HEADER + lines).join("\n"))
                @manifest_tmp.write "\n"
                path("META-INF").include @manifest_tmp.path, :as=>"MANIFEST.MF"
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
              name = section.has_key?("Name") ? ["Name: #{section["Name"]}"] : []
              name + section.except("Name").map { |name, value| "#{name}: #{value}" }.sort + [""]
            }.flatten.map { |line| manifest_wrap_at_72(line) }.flatten
          when Proc, Method
            manifest_lines_from(arg.call)
          when String
            arg.split("\n").map { |line| manifest_wrap_at_72(line) }.flatten
          else
            fail "Invalid manifest, expecting Hash, Array, file name/task or proc/method."
          end
        end

        def manifest_wrap_at_72(arg)
          #return arg.map { |line| manifest_wrap_at_72(line) }.flatten.join("\n") if Array === arg
          return arg if arg.size < 72
          [ arg[0..70], manifest_wrap_at_72(" " + arg[71..-1]) ]
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
      #   package(:jar).with(:manifest=>"src/MANIFEST.MF")
      #   package(:jar).meta_inf << file("README")
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
        #   package(:jar).with(:manifest=>"MANIFEST_MF")
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
      #   package(:war).with(:libs=>"log4j:log4j:jar:1.1")
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
            @classes.to_a.flatten.each { |classes| path("WEB-INF/classes").include classes, :as=>"." }
            path("WEB-INF/lib").include Buildr.artifacts(@libs) unless @libs.nil? || @libs.empty?
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
      #   package(:aar).with(:libs=>"log4j:log4j:jar:1.1")
      #
      #   filter.from("src/main/axis2").into("target").include("services.xml", "*.wsdl").using("http_port"=>"8080")
      #   package(:aar).wsdls.clear
      #   package(:aar).with(:services_xml=>_("target/services.xml"), :wsdls=>_("target/*.wsdl"))
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
            path("META-INF").include @wsdls
            path("META-INF").include @services_xml, :as=>["services.xml"] if @services_xml
            path("lib").include Buildr.artifacts(@libs) unless @libs.nil? || @libs.empty?
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
        # Need to run buildr before package, since package is often used as a dependency by tasks that
        # expect build to happen.
        project.task("package"=>project.task("build"))
        project.group ||= project.parent && project.parent.group || project.name
        project.version ||= project.parent && project.parent.version
        project.manifest ||= project.parent && project.parent.manifest ||
          { 'Build-By'=>ENV['USER'], 'Build-Jdk'=>Java.version,
            'Implementation-Title'=>project.comment || project.name,
            'Implementation-Version'=>project.version }
        project.meta_inf ||= project.parent && project.parent.meta_inf ||
          [project.file('LICENSE')].select { |file| File.exist?(file.to_s) }
      end


      # Options accepted by #package method for all package types.
      PACKAGE_OPTIONS = [:group, :id, :version, :type, :classifier] #:nodoc:

      # The project's identifier. Same as the project name, with colons replaced by dashes.
      # The ID for project foo:bar is foo-bar.
      attr_reader :id
      def id()
        name.gsub(":", "-")
      end

      # Group used for packaging. Inherited from parent project. Defaults to the top-level project name.
      attr_accessor :group

      # Version used for packaging. Inherited from parent project.
      attr_accessor :version

      # Manifest used for packaging. Inherited from parent project. The default value is a hash that includes
      # the Build-By, Build-Jdk, Implementation-Title and Implementation-Version values.
      # The later are taken from the project's comment (or name) and version number.
      attr_accessor :manifest

      # Files to always include in the package META-INF directory. The default value include
      # the LICENSE file if one exists in the project's base directory.
      attr_accessor :meta_inf

      # :call-seq:
      #   package(type, spec?) => task
      #
      # Defines and returns a package created by this project.
      #
      # The first argument declares the package type. For example, :jar to create a JAR file.
      # The package is an artifact that takes its artifact specification from the project.
      # You can override the artifact specification by passing various options in the second
      # argument, for example:
      #   package(:zip, :classifier=>"sources")
      #
      # Packages that are ZIP files provides various ways to include additional files, directories,
      # and even merge ZIPs together. Have a look at ZipTask for more information. In case you're
      # wondering, JAR and WAR packages are ZIP files.
      #
      # You can also enhance a JAR package using the ZipTask#with method that accepts the following options:
      # * :manifest -- Specifies how to create the MANIFEST.MF. By default, uses the project's
      #   #manifest property.
      # * :meta_inf -- Specifies files to be included in the META-INF directory. By default,
      #   uses the project's #meta-inf property.
      #
      # The WAR package supports the same options and adds a few more:
      # * :classes -- Directories of class files to include in WEB-INF/classes. Includes the compile
      #   target directory by default.
      # * :libs -- Artifacts and files to include in WEB-INF/libs. Includes the compile classpath
      #   dependencies by default.
      #
      # For example:
      #   define "project" do
      #     define "beans" do
      #       package :jar
      #     end
      #     define "webapp" do
      #       compile.with project("beans")
      #       package(:war).with :libs=>MYSQL_JDBC
      #     end
      #     package(:zip, :classifier=>"sources").include path_to(".")
      #  end
      #
      # Two other packaging types are:
      # * package :sources -- Creates a ZIP file with the source code and classifier "sources", for use by IDEs.
      # * package :javadoc -- Creates a ZIP file with the Javadocs and classifier "javadoc". You can use the
      #   javadoc method to further customize it.
      #
      # A package is also an artifact. The following tasks operate on packages created by the project:
      #   buildr upload     # Upload packages created by the project
      #   buildr install    # Install packages created by the project
      #   buildr package    # Create packages
      #   buildr uninstall  # Remove previously installed packages
      #
      # If you want to add additional packaging types, implement a method with the name package_as_[type]
      # that accepts two arguments, the file name and a hash of options. You can change the options and
      # file name, e.g. to add a classifier or change the file type. Your method may be called multiple times,
      # and must return the same file task on each call.
      def package(type = :jar, options = nil)
        options = options.nil? ? {} : options.dup
        options[:id] ||= self.id
        options[:group] ||= self.group
        options[:version] ||= self.version
        options[:type] = type
        file_name = path_to(:target, Artifact.hash_to_file_name(options))

        packager = method("package_as_#{type}") rescue
          fail("Don't know how to create a package of type #{type}")
        package = packager.call(file_name, options) { warn_deprecated "Yielding from package_as_ no longer necessary." }
        unless packages.include?(package)
          # Make it an artifact using the specifications, and tell it how to create a POM.
          package.extend ActsAsArtifact
          package.send :apply_spec, options.only(*Artifact::ARTIFACT_ATTRIBUTES)
          # Another task to create the POM file.
          pom = package.pom
          pom.enhance do
            mkpath File.dirname(pom.name), :verbose=>false
            File.open(pom.name, "w") { |file| file.write pom.pom_xml }
          end

          # We already run build before package, but we also need to do so if the package itself is
          # used as a dependency, before we get to run the package task.
          task "package"=>package
          package.enhance [task("build")]

          # Install the artifact along with its POM. Since the artifact (package task) is created
          # in the target directory, we need to copy it into the local repository. However, the
          # POM artifact (created by calling artifact on its spec) is already mapped to its right
          # place in the local repository, so we only need to invoke it.
          installed = file(Buildr.repositories.locate(package)=>package) { |task|
            verbose(Rake.application.options.trace || false) do
              mkpath File.dirname(task.name), :verbose=>false
              cp package.name, task.name
            end
            puts "Installed #{task.name}" if verbose
          }
          task "install"=>[installed, pom]
          task "uninstall" do |task|
            verbose(Rake.application.options.trace || false) do
              [ installed, pom ].map(&:to_s).each { |file| rm file if File.exist?(file) } 
            end
          end
          task("upload") { package.pom.invoke ; package.pom.upload ; package.upload }

          # Add the package to the list of packages created by this project, and
          # register it as an artifact. The later is required so if we look up the spec
          # we find the package in the project's target directory, instead of finding it
          # in the local repository and attempting to install it.
          packages << package
          Artifact.register package, pom
        end
        package
      end

      # :call-seq:
      #   packages() => tasks
      #
      # Returns all packages created by this project. A project may create any number of packages.
      #
      # This method is used whenever you pass a project to Buildr#artifact or any other method
      # that accepts artifact specifications and projects. You can use it to list all packages
      # created by the project. If you want to return a specific package, it is often more
      # convenient to call #package with the type.
      def packages()
        @packages ||= []
      end

      # :call-seq:
      #   package_with_sources(options?)
      #
      # Call this when you want the project (and all its sub-projects) to create a source distribution.
      # You can use the source distribution in an IDE when debugging.
      #
      # A source distribution is a ZIP package with the classifier "sources", which includes all the
      # sources used by the compile task.
      #
      # Packages use the project's manifest and meta_inf properties, which you can override by passing
      # different values (e.g. false to exclude the manifest) in the options.
      #
      # To create source distributions only for specific projects, use the :only and :except options,
      # for example:
      #   package_with_sources :only=>["foo:bar", "foo:baz"]
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
      # A JavaDoc distribution is a ZIP package with the classifier "javadoc", which includes all the
      # sources used by the compile task.
      #
      # Packages use the project's manifest and meta_inf properties, which you can override by passing
      # different values (e.g. false to exclude the manifest) in the options.
      #
      # To create JavaDoc distributions only for specific projects, use the :only and :except options,
      # for example:
      #   package_with_javadoc :only=>["foo:bar", "foo:baz"]
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

      def package_as_jar(file_name, options) #:nodoc:
        unless Rake::Task.task_defined?(file_name)
          rake_check_options options, *PACKAGE_OPTIONS + [:manifest, :meta_inf, :include]
          Java::Packaging::JarTask.define_task(file_name).tap do |jar|
            jar.with :manifest=>manifest, :meta_inf=>meta_inf
            [:manifest, :meta_inf].each do |option|
              if options.has_key?(option)
                warn_deprecated "The :#{option} option in package(:jar) is deprecated, please use package(:jar).with(:#{option}=>) instead."
                jar.with option=>options[option]
              end
            end
            if options[:include]
              warn_deprecated "The :include option in package(:jar) is deprecated, please use package(:jar).include(files) instead."
              jar.include options[:include]
            else
              jar.with compile.target unless compile.sources.empty?
              jar.with resources.target unless resources.sources.empty?
            end
          end
        else
          rake_check_options options, *PACKAGE_OPTIONS
        end
        file(file_name)
      end

      def package_as_war(file_name, options) #:nodoc:
        unless Rake::Task.task_defined?(file_name)
          rake_check_options options, *PACKAGE_OPTIONS + [:manifest, :meta_inf, :classes, :libs, :include]
          Java::Packaging::WarTask.define_task(file_name).tap do |war|
            war.with :manifest=>manifest, :meta_inf=>meta_inf
            [:manifest, :meta_inf].each do |option|
              if options.has_key?(option)
                warn_deprecated "The :#{option} option in package :war is deprecated, please use package(:war).with(:#{option}=>) instead."
                war.with option=>options[option]
              end
            end
            # Add libraries in WEB-INF lib, and classes in WEB-INF classes
            if options.has_key?(:classes)
              warn_deprecated "The :classes option in package(:war) is deprecated, please use package(:war).with(:classes=>) instead."
              war.with :classes=>options[:classes]
            else
              war.with :classes=>compile.target unless compile.sources.empty?
              war.with :classes=>resources.target unless resources.sources.empty?
            end
            if options.has_key?(:libs)
              warn_deprecated "The :libs option in package(:war) is deprecated, please use package(:war).with(:libs=>) instead."
              war.with :libs=>options[:libs].collect
            else
              war.with :libs=>compile.classpath
            end
            # Add included files, or the webapp directory.
            if options.has_key?(:include)
              warn_deprecated "The :include option in package(:war) is deprecated, please use package(:war).include(files) instead."
              war.include options[:include]
            else
              path_to("src/main/webapp").tap { |path| war.with path if File.exist?(path) }
            end
          end
        else
          rake_check_options options, *PACKAGE_OPTIONS
        end
        file(file_name)
      end

      def package_as_aar(file_name, options) #:nodoc:
        rake_check_options options, *PACKAGE_OPTIONS
        unless Rake::Task.task_defined?(file_name)
          Java::Packaging::AarTask.define_task(file_name).tap do |aar|
            aar.with :manifest=>manifest, :meta_inf=>meta_inf
            aar.with :wsdls=>path_to("src/main/axis2/*.wsdl")
            aar.with :services_xml=>path_to("src/main/axis2/services.xml") 
            aar.with compile.target unless compile.sources.empty?
            aar.with resources.target unless resources.sources.empty?
            aar.with :libs=>compile.classpath
          end
        end
        file(file_name)
      end

      def package_as_zip(file_name, options) #:nodoc:
        unless Rake::Task.task_defined?(file_name)
          rake_check_options options, *PACKAGE_OPTIONS + [:include]
          ZipTask.define_task(file_name).tap do |zip|
            if options[:include]
              warn_deprecated "The :include option in package(:zip) is deprecated, please use package(:zip).include(files) instead."
              zip.include options[:include]
            end
          end
        else
          rake_check_options options, *PACKAGE_OPTIONS
        end
        file(file_name)
      end

      def package_as_tar(file_name, options) #:nodoc:
        rake_check_options options, *PACKAGE_OPTIONS
        unless Rake::Task.task_defined?(file_name)
          TarTask.define_task(file_name)
        end
        file(file_name)
      end
      alias :package_as_tgz :package_as_tar

      def package_as_sources(file_name, options) #:nodoc:
        rake_check_options options, *PACKAGE_OPTIONS
        options.merge!(:type=>:zip, :classifier=>"sources")
        file_name = path_to(:target, Artifact.hash_to_file_name(options))
        ZipTask.define_task(file_name).tap { |zip| zip.include :from=>compile.sources } unless Rake::Task.task_defined?(file_name)
        file(file_name)
      end

      def package_as_javadoc(file_name, options) #:nodoc:
        rake_check_options options, *PACKAGE_OPTIONS
        options.merge!(:type=>:zip, :classifier=>"javadoc")
        file_name = path_to(:target, Artifact.hash_to_file_name(options))
        unless Rake::Task.task_defined?(file_name)
          ZipTask.define_task(file_name).tap { |zip| zip.include :from=>javadoc.target }
          javadoc.options[:windowtitle] ||= project.comment || project.name
        end
        file(file_name)
      end

    end

  end
end
