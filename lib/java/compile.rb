require "core/project"
require "core/build"
require "core/common"
require "java/artifact"
require "java/java"

module Buildr
  module Java

    # Wraps Javac in a task that does all the heavy lifting.
    #
    # Accepts multiple source directories that are invoked as prerequisites before compilation.
    # You can pass a task as a source directory, e.g. compile.from(apt).
    #
    # Likewise, classpath dependencies are invoked before compiling. All classpath dependencies
    # are evaluated as #artifacts, so you can pass artifact specifications and even projects.
    #
    # Creates a file task for the target directory, so executing that task as a dependency will
    # execute the compile task first.
    #
    # Compiler options are inherited form a parent task, e.g. the foo:bar:compile task inherits
    # its options from the foo:compile task. Even if foo is an empty project that does not compile
    # any classes itself, you can use it to set compile options for all its sub-projects.
    #
    # Normally, the project will take care of setting the source and target directory, and you
    # only need to set options and classpath dependencies. See Project#compile.
    class CompileTask < Rake::Task

      # Compiler options, accessible from CompileTask#options.
      #
      # Supported options are:
      # - warnings -- Generate warnings if true (opposite of -nowarn).
      # - deprecation -- Output source locations where deprecated APIs are used.
      # - source -- Source compatibility with specified release.
      # - target -- Class file compatibility with specified release.
      # - lint -- Value to pass to xlint argument. Use true to enable default lint
      #   options, or pass a specific setting as string or array of strings.
      # - debug -- Generate debugging info.
      # - other -- Array of options to pass to the Java compiler as is.
      #
      # For example:
      #   compile.options.warnings = true
      #   compile.options.source = options.target = "1.6"
      class Options

        include InheritedAttributes

        OPTIONS = [:warnings, :deprecation, :source, :target, :lint, :debug, :other]

        # Generate warnings (opposite of -nowarn).
        attr_accessor :warnings
        inherited_attr(:warnings) { verbose }
        # Output source locations where deprecated APIs are used.
        attr_accessor :deprecation
        inherited_attr :deprecation, false
        # Provide source compatibility with specified release.
        attr_accessor :source
        inherited_attr :source
        # Generate class files for specific VM version.
        attr_accessor :target
        inherited_attr :target
        # Values to pass to Xlint: string or array. Use true to enable
        # Xlint with no values.
        attr_accessor :lint
        inherited_attr :lint, false
        # Generate all debugging info.
        attr_accessor :debug
        inherited_attr(:debug) { Buildr.options.debug }
        # Array of arguments passed to the Java compiler as is.
        attr_accessor :other
        inherited_attr :other

        def initialize(parent = nil) #:nodoc:
          @parent = parent
        end

        attr_reader :parent # :nodoc:

        # Resets all the options.
        def clear()
          OPTIONS.each { |name| send "#{name}=", nil }
        end

        def to_s() #:nodoc:
          OPTIONS.inject({}){ |hash, name| hash[name] = send(name) ; hash }.reject{ |name,value| value.nil? }.inspect
        end

        # Returns Javac command line arguments from the set of options.
        def javac_args()
          args = []  
          args << "-nowarn" unless warnings
          args << "-verbose" if Rake.application.options.trace
          args << "-g" if debug
          args << "-deprecation" if deprecation
          args << "-source" << source.to_s if source
          args << "-target" << target.to_s if target
          case lint
          when Array
            args << "-Xlint:#{lint.join(',')}"
          when String
            args << "-Xlint:#{lint}"
          when true
            args << "-Xlint"
          end
          args.concat(other.to_a) if other
          args
        end

      end


      def initialize(*args) #:nodoc:
        super
        parent = Project.task_in_parent_project(name)
        if parent && parent.respond_to?(:options)
          @options = Options.new(parent.options)
        else
          @options = Options.new
        end
        @sources = []
        @classpath = []

        enhance do |task|
          mkpath target.to_s, :verbose=>false
          Java.javac source_files.keys, :sourcepath=>sources.map(&:to_s).select { |source| File.directory?(source) }.uniq,
            :classpath=>classpath, :output=>target, :javac_args=>options.javac_args, :name=>task.name
          # By touching the target we let other tasks know we did something,
          # and also prevent recompiling again for classpath dependencies.
          touch target.to_s, :verbose=>false
        end
      end

      # Source directories and files to compile.
      attr_accessor :sources

      # :call-seq:
      #   from(*sources) => self
      #
      # Adds source directories and files to compile, and returns self.
      #
      # For example:
      #   compile.from("src/java").into("classes").with("module1.jar")
      def from(*sources)  
        @sources |= sources.flatten
        self
      end

      # Classpath dependencies.
      attr_accessor :classpath

      # :call-seq:
      #   with(*artifacts) => self
      #
      # Adds files and artifacts as classpath dependencies, and returns self.
      #
      # Calls #artifacts on the arguments, so you can pass artifact specifications,
      # tasks, projects, etc. Use this rather than setting the classpath directly.
      #
      # For example:
      #   compile.with("module1.jar", "log4j:log4j:jar:1.0", project("foo"))
      def with(*specs)
        @classpath |= Buildr.artifacts(specs.flatten).uniq
        self
      end

      # The target directory for the generated class files.
      attr_reader :target

      # :call-seq:
      #   into(path) => self
      #
      # Sets the target directory and returns self. This will also set the compile task
      # as a prerequisite to a file task on the target directory.
      #
      # For example:
      #   compile(src_dir).into(target_dir).with(artifacts)
      # Both compile.invoke and file(target_dir).invoke will compile the source files.
      def into(path)
        path = File.expand_path(path.to_s)
        @target = file(path).enhance([self]) unless @target && @target.to_s == path
        self
      end

      # Returns the compiler options.
      attr_reader :options

      # :call-seq:
      #   using(options) => self
      #
      # Sets the compiler options from a hash and returns self.
      #
      # For example:
      #   compile.using(:warnings=>true, :source=>"1.5")
      def using(*args)
        args.pop.each { |key, value| options.send "#{key}=", value } if Hash === args.last
        args.each { |key| options.send "#{key}=", value = true }
        self
      end

      def timestamp() #:nodoc:
        # If we compiled successfully, then the target directory reflects that.
        # If we didn't, see needed?
        target ? target.timestamp : Rake::EARLY
      end

      def needed?() #:nodoc:
        return false if source_files.empty?
        return true unless File.exist?(target.to_s)
        return true if source_files.any? { |j, c| !File.exist?(c) || File.stat(j).mtime > File.stat(c).mtime }
        oldest = source_files.map { |j, c| File.stat(c).mtime }.min
        return classpath.any? { |path| application[path].timestamp > oldest }
      end

      def prerequisites() #:nodoc:
        super + classpath + sources
      end

      def invoke_prerequisites() #:nodoc:
        prerequisites.each { |n| application[n, @scope].invoke }
      end

      # Returns the files to compile. This list is derived from the list of sources,
      # expanding directories into files, and includes only source files that are
      # newer than the corresponding class file. Includes all files if one or more
      # classpath dependency has been updated.
      def source_files()
        @source_files ||= @sources.map(&:to_s).inject({}) do |map, source|
          raise "Compile task #{name} has source files, but no target directory" unless target
          target_dir = target.to_s
          if File.directory?(source)
            base = Pathname.new(source)
            FileList["#{source}/**/*.java"].reject { |file| File.directory?(file) }.
              each { |file| map[file] = File.join(target_dir, Pathname.new(file).relative_path_from(base).to_s.ext('.class')) }
          else
            map[source] = File.join(target_dir, File.basename(source).ext('.class'))
          end
          map
        end
      end

    end

 
    # The resources task is executed by the compile task to copy resource files over
    # to the target directory. You can enhance this task in the normal way, but mostly
    # you will use the task's filter.
    #
    # For example:
    #   resources.filter.using "Copyright"=>"Acme Inc, 2007"
    class ResourcesTask < Rake::Task

      # Returns the filter used to copy resources over. See Buildr::Filter.
      attr_reader :filter

      def initialize(*args) #:nodoc:
        super
        @filter = Buildr::Filter.new
        enhance { filter.run unless filter.sources.empty? }
      end

      # :call-seq:
      #   include(*files) => self
      #
      # Includes the specified files in the filter and returns self.
      def include(*files)
        filter.include *files
        self
      end

      # :call-seq:
      #   exclude(*files) => self
      #
      # Excludes the specified files in the filter and returns self.
      def exclude(*files)
        filter.exclude *files
        self
      end

      # :call-seq:
      #   from(*sources) => self
      #
      # Adds additional directories from which to copy resources.
      #
      # For example:
      #   resources.from _("src/etc")
      def from(*sources)
        filter.from *sources
        self
      end

      # *Deprecated* Use #sources instead.
      def source()
        warn_deprecated "Please use sources instead."
        filter.source
      end

      # Returns the list of source directories (each being a file task).
      def sources()
        filter.sources
      end

      # :call-seq:
      #   target() => task
      #
      # Returns the filter's target directory as a file task.
      def target()
        filter.target
      end

      def prerequisites() #:nodoc:
        super + filter.sources.flatten
      end

    end


    # A convenient task for creating Javadocs from the project's compile task. Minimizes all
    # the hard work to calling #from and #using.
    #
    # For example:
    #   javadoc.from(projects("myapp:foo", "myapp:bar")).using(:windowtitle=>"My App")
    # Or, short and sweet:
    #   desc "My App"
    #   define "myapp" do
    #     . . .
    #     javadoc projects("myapp:foo", "myapp:bar")
    #   end
    class JavadocTask < Rake::Task

      def initialize(*args) #:nodoc:
        super
        @options = {}
        @classpath = []
        @sourcepath = []
        @files = FileList[]
        enhance do |task|
          rm_rf target.to_s, :verbose=>false
          Java.javadoc source_files, options.merge(:classpath=>classpath, :sourcepath=>sourcepath, :name=>name, :output=>target.to_s)
          touch target.to_s, :verbose=>false
        end
      end

      # The target directory for the generated Javadoc files.
      attr_reader :target

      # :call-seq:
      #   into(path) => self
      #
      # Sets the target directory and returns self. This will also set the Javadoc task
      # as a prerequisite to a file task on the target directory.
      #
      # For example:
      #   package :zip, :classifier=>"docs", :include=>javadoc.target
      def into(path)
        path = File.expand_path(path.to_s)
        @target = file(path).enhance([self]) unless @target && @target.to_s == path
        self
      end

      # :call-seq:
      #   include(*files) => self
      #
      # Includes additional source files and directories when generating the documentation
      # and returns self. When specifying a directory, includes all .java files in that directory.
      def include(*files)
        @files.include *files
        self
      end

      # :call-seq:
      #   exclude(*files) => self
      #
      # Excludes source files and directories from generating the documentation.
      def exclude(*files)
        @files.exclude *files
        self
      end

      # Classpath dependencies.
      attr_accessor :classpath

      # :call-seq:
      #   with(*artifacts) => self
      #
      # Adds files and artifacts as classpath dependencies, and returns self.
      def with(*specs)
        @classpath |= Buildr.artifacts(specs.flatten).uniq
        self
      end

      # Additional sourcepaths that are not part of the documented files.
      attr_accessor :sourcepath
        
      # Returns the Javadoc options.
      attr_reader :options

      # :call-seq:
      #   using(options) => self
      #
      # Sets the Javadoc options from a hash and returns self.
      #
      # For example:
      #   javadoc.using :windowtitle=>"My application"
      def using(*args)
        args.pop.each { |key, value| @options[key.to_sym] = value } if Hash === args.last
        args.each { |key| @options[key.to_sym] = true }
        self
      end

      # :call-seq:
      #   from(*sources) => self
      #
      # Includes files, directories and projects in the Javadoc documentation and returns self.
      #
      # You can call this method with Java source files and directories containing Java source files
      # to include these files in the Javadoc documentation, similar to #include. You can also call
      # this method with projects. When called with a project, it includes all the source files compiled
      # by that project and classpath dependencies used when compiling.
      #
      # For example:
      #   javadoc.from projects("myapp:foo", "myapp:bar")
      def from(*sources)
        sources.flatten.each do |source|
          case source
          when Project
            self.include source.compile.sources
            self.with source.compile.classpath 
          when Rake::Task, String
            self.include source
          else
            fail "Don't know how to generate Javadocs from #{source || 'nil'}"
          end
        end
        self
      end

      def prerequisites() #:nodoc:
        super + @files + classpath + sourcepath
      end

      def source_files() #:nodoc:
        @source_files ||= @files.map(&:to_s).
          map { |file| File.directory?(file) ? FileList[File.join(file, "**/*.java")] : file }.
          flatten.reject { |file| @files.exclude?(file) }
      end

      def needed?() #:nodoc:
        return false if source_files.empty?
        return true unless File.exist?(target.to_s)
        source_files.map { |src| File.stat(src.to_s).mtime }.max > File.stat(target.to_s).mtime
      end

    end


    # Methods added to Project for compiling, handling of resources and documentation.
    module Compile

      include Extension

      first_time do
        # Local task to execute the compile task of the current project.
        # This task is not itself a compile task.
        desc "Compile all projects"
        Project.local_task("compile") { |name| "Compiling #{name}" }
        desc "Create the Javadocs for this project"
        Project.local_task("javadoc")
      end
      
      before_define do |project|
        prepare = task("prepare")
        # Resources task is a filter.
        resources = Java::ResourcesTask.define_task("resources")
        project.path_to("src/main/resources").tap { |dir| resources.from dir if File.exist?(dir) }
        # Compile task requires prepare and performs resources, if anything compiled.
        compile = Java::CompileTask.define_task("compile"=>[prepare, resources])
        project.path_to("src/main/java").tap { |dir| compile.from dir if File.exist?(dir) }
        compile.into project.path_to(:target, "classes")
        resources.filter.into project.compile.target
        Java::JavadocTask.define_task("javadoc"=>prepare).tap do |javadoc|
          javadoc.into project.path_to(:target, "javadoc")
          javadoc.using :windowtitle=>project.comment || project.name
        end
        project.recursive_task("compile")
      end

      after_define do |project|
        # This comes last because the target path may change.
        project.build project.compile.target
        # This comes last so we can determine all the source paths and classpath dependencies.
        project.javadoc.from project
        project.clean { verbose(false) { rm_rf project.compile.target.to_s } }
      end


      # *Deprecated* Add a prerequisite to the compile task instead.
      def prepare(*prereqs, &block)
        warn_deprecated "Add a prerequisite to the compile task instead of using the prepare task."
        task("prepare").enhance prereqs, &block
      end

      # :call-seq:
      #   compile(*sources) => CompileTask
      #   compile(*sources) { |task| .. } => CompileTask
      #
      # The compile task does what its name suggests. This method returns the project's
      # CompileTask. It also accepts a list of source directories and files to compile
      # (equivalent to calling CompileTask#from on the task), and a block for any
      # post-compilation work.
      #
      # The compile task will pick all the source files in the src/main/java directory,
      # and unless specified, compile them into the target/classes directory. It will pick
      # the default values for compiler options from the parent project's compile task.
      #
      # For example:
      #   # Force target compatibility.
      #   compile.options.source = "1.6"
      #   # Include Apt-generated source files.
      #   compile.from apt
      #   # Include Log4J and the api sub-project artifacts.
      #   compile.with "log4j:log4j:jar:1.2", project("api")
      #   # Run the OpenJPA bytecode enhancer after compilation.
      #   compile { open_jpa_enhance }
      #
      # For more information, see Java::CompileTask.
      def compile(*sources, &block)
        task("compile").from(sources).enhance &block
      end

      # :call-seq:
      #   resources(*prereqs) => ResourcesTask
      #   resources(*prereqs) { |task| .. } => ResourcesTask
      #
      # The resources task is executed by the compile task to copy resources files
      # from the resource directory into the target directory.
      #
      # This method returns the project's resources task. It also accepts a list of
      # prerequisites and a block, used to enhance the resources task.
      #
      # By default the resources task copies files from the src/main/resources into the
      # same target directory as the #compile task. It does so using a filter that you
      # can access by calling resources.filter (see Buildr::Filter).
      #
      # For example:
      #   resources.from _("src/etc")
      #   resources.filter.using "Copyright"=>"Acme Inc, 2007"
      def resources(*prereqs, &block)
        task("resources").enhance prereqs, &block
      end

      # :call-seq:
      #   javadoc(*sources) => JavadocTask
      #
      # This method returns the project's Javadoc task. It also accepts a list of source files,
      # directories and projects to include when generating the Javadocs.
      #
      # By default the Javadoc task uses all the source directories from compile.sources and generates
      # Javadocs in the target/javadoc directory. This method accepts sources and adds them by calling
      # JavadocsTask#from.
      #
      # For example, if you want to generate Javadocs for a given project that includes all source files
      # in two of its sub-projects:
      #   javadoc projects("myapp:foo", "myapp:bar").using(:windowtitle=>"Docs for foo and bar")
      def javadoc(*sources, &block)
        task("javadoc").from(*sources).enhance &block
      end

    end

  end


  class Options

    # Returns the debug option (environment variable DEBUG).
    def debug()
      (ENV["DEBUG"] || ENV["debug"]) !~ /(no|off|false)/
    end

    # Sets the debug option (environment variable DEBUG).
    #
    # You can turn this option off directly, or by setting the environment variable
    # DEBUG to "no". For example:
    #   buildr build DEBUG=no
    #
    # The release tasks runs a build with <tt>DEBUG=no</tt>.
    def debug=(flag)
      ENV["debug"] = nil
      ENV["DEBUG"] = flag.to_s
    end

  end

end
