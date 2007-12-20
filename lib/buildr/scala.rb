require "java/java"

# TODO List
# -Eclipse support
# -SUnit
# -Cleanup compiler options

module Buildr
  module Scala

    class << self
      def scala_home
        ENV["SCALA_HOME"]
      end

      def scala_lib
        scala_lib = scala_home + "/lib/scala-library.jar"
      end

      def scalac(*args)
        options = Hash === args.last ? args.pop : {}
        rake_check_options options, :classpath, :sourcepath, :output, :scalac_args, :name

        files = args.flatten.each { |f| f.invoke if f.respond_to?(:invoke) }.map(&:to_s).
          collect { |arg| File.directory?(arg) ? FileList["#{arg}/**/*.scala"] : arg }.flatten
        name = options[:name] || Dir.pwd
        return if files.empty?

        fail "Missing SCALA_HOME environment variable" unless ENV["SCALA_HOME"]
        fail "Invalid SCALA_HOME environment variable" unless File.directory? ENV["SCALA_HOME"]

        cmd_args = []
        use_fsc = !(ENV["USE_FSC"] =~ /^(no|off|false)$/i)
        classpath = classpath_from(options)
        scala_cp = [ classpath,  FileList["#{scala_home}/lib/*"] ].flatten.join(File::PATH_SEPARATOR)
        cmd_args << "-cp" << scala_cp unless scala_cp.empty?
        cmd_args << "-sourcepath" << options[:sourcepath].join(File::PATH_SEPARATOR) if options[:sourcepath]
        cmd_args << "-d" << options[:output].to_s if options[:output]
        cmd_args += options[:scalac_args].flatten if options[:scalac_args]
        cmd_args += files
        unless Rake.application.options.dryrun
          puts "Compiling #{files.size} source files in #{name}" if verbose
          puts (["scalac"] + cmd_args).join(" ") if Rake.application.options.trace
          if use_fsc
            system ([ENV["SCALA_HOME"]+"/bin/fsc"] + cmd_args).join(" ")
            else
            Java.wrapper do |jw|
              jw.import("scala.tools.nsc.Main").main(cmd_args) == 0 or
              fail "Failed to compile, see errors above"
            end
          end
        end
      end

    protected

      # :call-seq:
      #    classpath_from(options) => files
      #
      # Extracts the classpath from the options, expands it by calling artifacts, invokes
      # each of the artifacts and returns an array of paths.
      def classpath_from(options)
        classpath = (options[:classpath] || []).collect
        Buildr.artifacts(classpath).each { |t| t.invoke if t.respond_to?(:invoke) }.map(&:to_s)
      end
    end # Scala << self


    # !! This is mostly a copy-paste Buildr:Java:CompileTask !!
    #
    # Wraps Scalac in a task that does all the heavy lifting.
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
    class ScalaCompilerTask < Rake::Task

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
      # - other -- Array of options to pass to the Scalac compiler as is.
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
        # Array of arguments passed to the Scalac compiler as is.
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

        # Returns Scalac command line arguments from the set of options.
        def scalac_args()
          args = []
          args << "-nowarn" unless warnings
          args << "-verbose" if Rake.application.options.trace
          args << "-g" if debug
          args << "-deprecation" if deprecation
          args << "-source" << source.to_s if source
          args << "-target:jvm-" + target.to_s if target
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
        parent = Rake::Task["^scalac"] if name[":"] # Only if in namespace
        if parent && parent.respond_to?(:options)
          @options = Options.new(parent.options)
        else
          @options = Options.new
        end
        @sources = []
        @classpath = []

        enhance do |task|
          mkpath target.to_s, :verbose=>false
          Scala.scalac source_files.keys, :sourcepath=>sources.map(&:to_s).select { |source| File.directory?(source) }.uniq,
            :classpath=>classpath, :output=>target, :scalac_args=>options.scalac_args, :name=>task.name
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
      #   compile.from("src/scala").into("classes").with("module1.jar")
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
            FileList["#{source}/**/*.scala"].
              each { |file| map[file] = File.join(target_dir, Pathname.new(file).relative_path_from(base).to_s.ext(".class")) }
          else
            map[source] = File.join(target_dir, File.basename(source).ext(".class"))
          end
          map
        end
      end

      def scala_lib
        Scala.scala_lib
      end
    end # ScalaCompilerTask


    include Extension

    first_time do
      # Local task to execute the Scalac compile task of the current project.
      # This task is not itself a compile task.
      desc "Compile all scalac projects"
      Project.local_task("scalac") { |name| "Compiling scala sources for #{name}" }
    end

    before_define do |project|
      # Scalac runs after compile task (and therefore, after "prepare" and "resources")
      scalac = Scala::ScalaCompilerTask.define_task("scalac"=>[task("compile")])
      project.path_to("src/main/scala").tap { |dir| scalac.from dir if File.exist?(dir) }
      scalac.into project.path_to(:target, "classes")
      project.recursive_task("scalac")
    end
  
    after_define do |project|
      # This comes last because the target path may change.
      project.packages.each do |p|
        p.with project.scalac.target if p.type == :jar
        p.classes = project.scalac.target if p.type == :war
      end
      # Work-in-progress
      #project.task("eclipse").classpathContainers 'ch.epfl.lamp.sdt.launching.SCALA_CONTAINER'

      project.build project.scalac.target
      project.clean { verbose(false) { rm_rf project.scalac.target.to_s } }
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
    # The compile task will pick all the source files in the src/main/scala directory,
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
    # For more information, see Scala::ScalaCompilerTask.
    def scalac(*sources, &block)
      task("scalac").from(sources).enhance &block
    end

end # Buildr

class Buildr::Project
  include Buildr::Scala
end
