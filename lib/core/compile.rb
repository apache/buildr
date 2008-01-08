require "core/common"

module Buildr

  # The underlying compiler used by CompileTask.
  # To add a new compiler, extend Compiler::Base and add your compiler using:
  #   Buildr::Compiler.add MyCompiler
  module Compiler

    class << self

      # Returns true if the specified compiler exists.
      def has?(name)
        @compilers.has_key?(name.to_sym)
      end

      # Select a compiler by its name.
      def select(name)
        @compilers[name.to_sym] or raise ArgumentError, "No #{name} compiler available. Did you install it?"
      end

      # Identify which compiler applies based on one of two arguments:
      # * :sources -- List of source directories, attempts to find applicable files there (e.g. Java source files).
      # * :source -- The source directory (src/main, src/test), from which it will look up a particular source
      #     directory (e.g. src/main/java).
      def identify(from)
        @compilers.values.detect { |compiler| compiler.identify?(from) }
      end

      # Adds a compiler to the list of supported compiler.
      #   
      # For example:
      #   Buildr::Compiler.add Buildr::Javac
      def add(compiler)
        compiler = compiler.new if Class === compiler
        @compilers[compiler.name.to_sym] = compiler
      end

      # Returns a list of available compilers.
      def compilers
        @compilers.values.clone
      end

    end

    @compilers = {}


    # Base class for all compilers, with common functionality.  Extend and over-ride as you see fit
    # (see Javac as an example).
    class Base #:nodoc:

      def initialize(args = {})
        args[:name] ||= self.class.name.split('::').last.downcase.to_sym
        args[:language] ||= args[:name]
        args[:source_path] ||= args[:language].to_s
        args[:source_ext] ||= ".#{args[:language]}"
        args.each { |name, value| instance_variable_set "@#{name}", value }
      end

      # Compiler name (e.g. :javac).
      attr_reader :name
      # Compiled language (e.g. :java).
      attr_reader :language
      # Common path for source files (e.g. 'java').
      attr_reader :source_path
      # Extension for source files (e.g. '.java').
      attr_reader :source_ext
      # Common path for target files (e.g. 'classes').
      attr_reader :target_path
      # Extension for target files (e.g. '.class').
      attr_reader :target_ext
      # The default packaging type (e.g. :jar).
      attr_reader :packaging

      # Used by Compiler.identify to determine if this compiler applies to the current project.
      # The default implementation looks for either the supplied source directories, or the
      # #source_path directory, depending on arguments, for files with #source_ext extension.
      def identify?(from)
        paths = from[:sources] || Array(File.join(from[:source], source_path))
        !Dir[*paths.map { |path| File.join(path, "**/*#{source_ext}") }].empty?
      end

      # Once selected, this method is called to configured the task for this compiler.
      # You can extend this to set up common source directories, the target directory,
      # default compiler options, etc.  The default implementation adds the source directory
      # from {source}/{source_path} and sets the target directory to {target}/{target_path}
      # if not already set.
      def configure(task, source, target)
        task.from File.join(source, source_path) if task.sources.empty? && File.exist?(File.join(source, source_path))
        task.into File.join(target, target_path) unless task.target
      end

      # The compile map is a hash that associates source files with target files based
      # on a list of source directories and target directory.  The compile task uses this
      # to determine if there are source files to compile, and which source files to compile.
      # The default method maps all files in the source directories with #source_ext into
      # paths in the target directory with #target_ext (e.g. 'source/foo.java'=>'target/foo.class').
      def compile_map(sources, target)
        sources.inject({}) do |map, source|
          if File.directory?(source)
            base = Pathname.new(source)
            FileList["#{source}/**/*#{source_ext}"].reject { |file| File.directory?(file) }.
              each { |file| map[file] = File.join(target, Pathname.new(file).relative_path_from(base).to_s.ext(target_ext)) }
          else
            map[source] = File.join(target, File.basename(source).ext(target_ext))
          end
          map
        end
      end

    private

      # Use this to copy options used by this compiler from the parent, for example,
      # if this task is 'foo:bar:compile', copy options set in the parent task 'foo:compile'.
      #
      # For example:
      #   def configure(task, source, target)
      #     super
      #     update_options_from_parent! task, OPTIONS
      #     . . .
      #   end
      def update_options_from_parent!(task, supported)
        parent = Project.task_in_parent_project(task.name)
        if parent.respond_to?(:options)
          missing = supported.flatten - task.options.to_hash.keys
          missing.each { |option| task.options[option] = parent.options[option] }
        end
      end

      # Use this to complain about CompileTask options not supported by this compiler.
      #
      # For example:
      #   def compile(files, task)
      #     check_options task, OPTIONS
      #     . . .
      #   end
      def check_options(task, supported)
        unsupported = task.options.to_hash.keys - supported.flatten
        raise ArgumentError, "No such option: #{unsupported.join(' ')}" unless unsupported.empty?
      end

    end

  end


  # Compile task.
  #
  # Attempts to determine which compiler to use based on the project layout, for example,
  # uses the Javac compiler if it finds any .java files in src/main/java.  You can also
  # select the compiler explicitly:
  #   compile.using(:scalac)
  #
  # Accepts multiple source directories that are invoked as prerequisites before compilation.
  # You can pass a task as a source directory:
  #   compile.from(apt)
  #
  # Likewise, dependencies are invoked before compiling. All dependencies are evaluated as
  # #artifacts, so you can pass artifact specifications and even projects:
  #   compile.with("module1.jar", "log4j:log4j:jar:1.0", project("foo"))
  #
  # Creates a file task for the target directory, so executing that task as a dependency will
  # execute the compile task first.
  #
  # Compiler options are inherited form a parent task, e.g. the foo:bar:compile task inherits
  # its options from the foo:compile task. Even if foo is an empty project that does not compile
  # any classes itself, you can use it to set compile options for all its sub-projects.
  #
  # Normally, the project will take care of setting the source and target directory, and you
  # only need to set options and dependencies. See Project#compile.
  class CompileTask < Rake::Task

    def initialize(*args) #:nodoc:
      super
      parent = Project.task_in_parent_project(name)
      @options = OpenObject.new
      @sources = []
      @dependencies = []

      enhance do |task|
        unless sources.empty?
          raise 'No compiler selected and can\'t determine which compiler to use' unless compiler
          raise 'No target directory specified' unless target
          mkpath target.to_s, :verbose=>false
          files = compile_map.keys
          unless files.empty?
            puts "Compiling #{files.size} source files in #{task.name}" if verbose
            @compiler.compile(files, task)
          end
          # By touching the target we let other tasks know we did something,
          # and also prevent recompiling again for dependencies.
          touch target.to_s, :verbose=>false
        end
      end
    end

    # Source directories.
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

    # *Deprecated*: Use dependencies instead.
    def classpath
      warn_deprecated 'Use dependencies instead.'
      dependencies
    end

    # *Deprecated*: Use dependencies= instead.
    def classpath=(artifacts)
      warn_deprecated 'Use dependencies= instead.'
      self.dependencies = artifacts
    end

    # Compilation dependencies.
    attr_accessor :dependencies

    # :call-seq:
    #   with(*artifacts) => self
    #
    # Adds files and artifacts as dependencies, and returns self.
    #
    # Calls #artifacts on the arguments, so you can pass artifact specifications,
    # tasks, projects, etc. Use this rather than setting the dependencies array directly.
    #
    # For example:
    #   compile.with("module1.jar", "log4j:log4j:jar:1.0", project("foo"))
    def with(*specs)
      @dependencies |= Buildr.artifacts(specs.flatten).uniq
      self
    end

    # The target directory for the compiled code.
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
      @target = file(path.to_s).enhance([self]) unless @target.to_s == path.to_s
      self
    end

    # Returns the compiler options.
    attr_reader :options

    # :call-seq:
    #   using(options) => self
    #
    # Sets the compiler options from a hash and returns self.  Can also be used to
    # select the compiler.
    #
    # For example:
    #   compile.using(:warnings=>true, :source=>"1.5")
    #   compile.using(:scala)
    def using(*args)
      args.pop.each { |key, value| options.send "#{key}=", value } if Hash === args.last
      self.compiler = args.pop until args.empty?
      self
    end

    # Returns the compiler if known.  The compiler is either automatically selected
    # based on existing source directories (e.g. src/main/java), or by requesting
    # a specific compiler (see #using).
    def compiler
      self.compiler = Compiler.identify(:sources=>sources) unless sources.empty? || @compiler
      @compiler && @compiler.name
    end

    # Returns the compiled language, if known.  See also #compiler.
    def language
      compiler && @compiler.language
    end

    # Returns the default packaging type for this compiler, if known.
    def packaging
      compiler && @compiler.packaging
    end

    def timestamp #:nodoc:
      # If we compiled successfully, then the target directory reflects that.
      # If we didn't, see needed?
      target ? target.timestamp : Rake::EARLY
    end

  protected

    # Selects which compiler to use.
    def compiler=(compiler) #:nodoc:
      return self unless compiler
      compiler = Compiler.select(compiler) unless Compiler::Base === compiler
      unless @compiler == compiler
        raise "#{@compiler} compiler already selected for this project" if @compiler
        @compiler = compiler
        @compiler.configure(self, @associate[:source], @associate[:target])
      end
      self
    end

    def associate(source, target) #:nodoc:
      @associate = { :source=>source, :target=>target }
      self.compiler = Compiler.identify(:source=>source)
    end

  private

    def needed? #:nodoc:
      return false if Array(sources).empty?
      # Fail during invoke.
      return true unless @compiler && target
      # No need to check further.
      return false if compile_map.empty?
      return true unless File.exist?(target.to_s)
      return true if compile_map.any? { |source, target| !File.exist?(target) || File.stat(source).mtime > File.stat(target).mtime }
      oldest = compile_map.map { |source, target| File.stat(target).mtime }.min
      return dependencies.any? { |path| application[path].timestamp > oldest }
    end

    def invoke_prerequisites(args, chain) #:nodoc:
      @prerequisites |= dependencies + Array(sources)
      super
    end

    # Creates and caches the compile map.
    def compile_map #:nodoc:
      @compile_map ||= @compiler.compile_map(@sources = Array(@sources).map(&:to_s).uniq, target.to_s)
    end

  end


  # The resources task is executed by the compile task to copy resource files over
  # to the target directory. You can enhance this task in the normal way, but mostly
  # you will use the task's filter.
  #
  # For example:
  #   resources.filter.using 'Copyright'=>'Acme Inc, 2007'
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
    #   resources.from _("src/etc')
    def from(*sources)
      filter.from *sources
      self
    end

    # Returns the list of source directories (each being a file task).
    def sources
      filter.sources
    end

    # :call-seq:
    #   target() => task
    #
    # Returns the filter's target directory as a file task.
    def target
      filter.target
    end

    def prerequisites #:nodoc:
      super + filter.sources.flatten
    end

  end


  # Methods added to Project for compiling, handling of resources and generating source documentation.
  module Compile

    include Extension

    first_time do
      desc 'Compile all projects'
      Project.local_task('compile') { |name| "Compiling #{name}" }
    end

    before_define do |project|
      resources = ResourcesTask.define_task('resources')
      project.path_to(:source, :main, :resources).tap { |dir| resources.from dir if File.exist?(dir) }
      resources.filter.into project.path_to(:target, :main, :resources)
      resources.filter.using Buildr.profile

      compile = CompileTask.define_task('compile'=>resources)
      compile.send :associate, project.path_to(:source, :main), project.path_to(:target, :main)
      project.recursive_task('compile')
    end

    after_define do |project|
      file(project.resources.target.to_s => project.resources) if project.resources.target
      if project.compile.target
        # This comes last because the target path is set inside the project definition.
        project.build project.compile.target
        project.clean do
          verbose(false) do
            rm_rf project.compile.target.to_s
          end
        end
      end
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
    # The compile task attempts to guess which compiler to use.  For example, if it finds
    # any Java files in the src/main/java directory, it will use the Java compiler and
    # create class files in the target/classes directory.
    #
    # You can also configure it yourself by telling it which compiler to use, pointing
    # it as source directories and chooing a different target directory.
    #
    # For example:
    #   # Include Log4J and the api sub-project artifacts.
    #   compile.with 'log4j:log4j:jar:1.2', project('api')
    #   # Include Apt-generated source files.
    #   compile.from apt
    #   # For JavaC, force target compatibility.
    #   compile.options.source = '1.6'
    #   # Run the OpenJPA bytecode enhancer after compilation.
    #   compile { open_jpa_enhance }
    #   # Pick a given compiler.
    #   compile.using(:scalac).from('src/scala')
    #
    # For more information, see CompileTask.
    def compile(*sources, &block)
      task('compile').from(sources).enhance &block
    end

    # :call-seq:
    #   resources(*prereqs) => ResourcesTask
    #   resources(*prereqs) { |task| .. } => ResourcesTask
    #
    # The resources task is executed by the compile task to copy resources files
    # from the resource directory into the target directory. By default the resources
    # task copies files from the src/main/resources into the target/resources directory.
    #
    # This method returns the project's resources task. It also accepts a list of
    # prerequisites and a block, used to enhance the resources task.
    #
    # Resources files are copied and filtered (see Buildr::Filter for more information).
    # The default filter uses the profile properties for the current environment.
    #
    # For example:
    #   resources.from _('src/etc')
    #   resources.filter.using 'Copyright'=>'Acme Inc, 2007'
    #
    # Or in your profiles.yaml file:
    #   common:
    #     Copyright: Acme Inc, 2007
    def resources(*prereqs, &block)
      task('resources').enhance prereqs, &block
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


class Buildr::Project
  include Buildr::Compile
end
