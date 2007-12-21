require "core/common"

module Buildr


  module Compiler

    COMPILERS = []

    class << self

      def select(compiler)
        cls = COMPILERS.detect { |cls| cls.compiler_name == compiler.to_s }
        raise "No #{compiler} compiler available. Did you install it?" unless cls
        cls.new
      end

      def identify(project)
        cls = COMPILERS.detect { |compiler| compiler.identify?(project) }
        cls && cls.new
      end

    end


    class Base

      def self.compiler_name
        name.split('::').last.downcase
      end

      def name
        self.class.compiler_name
      end

    end


    class Java < Base

      COMPILERS << self

      def self.identify?(project)
        !Dir[project.path_to('src/main/java/**/*.java')].empty?
      end

      def configure(task, project)
        task.options.warnings ||= verbose
        task.options.deprecation ||= false
        task.options.lint ||= false
        task.options.debug ||= Buildr.options.debug
        task.from project.path_to('src/main/java') if task.sources.empty?
        task.into project.path_to(:target, 'classes') unless task.target
      end

      def compile(sources, target, dependencies, options, name)
        ::Buildr::Java.javac source_files(sources, target).keys, :sourcepath=>sources.map(&:to_s).select { |source| File.directory?(source) }.uniq,
          :classpath=>dependencies, :output=>target, :javac_args=>javac_args_from(options), :name=>name
      end

      # Returns the files to compile. This list is derived from the list of sources,
      # expanding directories into files, and includes only source files that are
      # newer than the corresponding class file. Includes all files if one or more
      # classpath dependency has been updated.
      def source_files(sources, target)
        @source_files ||= sources.map(&:to_s).inject({}) do |map, source|
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

      def javac_args_from(options)
        args = []  
        args << '-nowarn' unless options.warnings
        args << '-verbose' if Rake.application.options.trace
        args << '-g' if options.debug
        args << '-deprecation' if options.deprecation
        args << '-source' << options.source.to_s if options.source
        args << '-target' << options.target.to_s if options.target
        case options.lint
          when Array; args << "-Xlint:#{options.lint.join(',')}"
          when String; args << "-Xlint:#{options.lint}"
          when true; args << '-Xlint'
        end
        options.other = options.other.map { |name, value| [ "-#{name}", value.to_s ] }.flatten if Hash === options.other
        args + Array(options.other)
      end

    end

  end




=begin
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
  module Javac

    def self.extended(base)
      base.instance_variable_set(:@classpath, [])
      base.options.warnings ||= verbose
      base.options.deprecation ||= false
      base.options.lint ||= false
      base.options.debug ||= Buildr.options.debug
    end

    def self.recognize?(project)
      File.exist?(project.path_to('src/main/java'))
    end

    def compile
      Java.javac source_files.keys, :sourcepath=>sources.map(&:to_s).select { |source| File.directory?(source) }.uniq,
        :classpath=>classpath, :output=>target, :javac_args=>javac_args, :name=>name
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

    def prerequisites #:nodoc:
      super + classpath + sources
    end

    # Returns the files to compile. This list is derived from the list of sources,
    # expanding directories into files, and includes only source files that are
    # newer than the corresponding class file. Includes all files if one or more
    # classpath dependency has been updated.
    def source_files
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

    def needed? #:nodoc:
      return false if source_files.empty?
      return true unless File.exist?(target.to_s)
      return true if source_files.any? { |j, c| !File.exist?(c) || File.stat(j).mtime > File.stat(c).mtime }
      oldest = source_files.map { |j, c| File.stat(c).mtime }.min
      return classpath.any? { |path| application[path].timestamp > oldest }
    end

    def javac_args
      args = []  
      args << '-nowarn' unless options.warnings
      args << '-verbose' if Rake.application.options.trace
      args << '-g' if options.debug
      args << '-deprecation' if options.deprecation
      args << '-source' << options.source.to_s if options.source
      args << '-target' << options.target.to_s if options.target
      case options.lint
        when Array; args << "-Xlint:#{options.lint.join(',')}"
        when String; args << "-Xlint:#{options.lint}"
        when true; args << '-Xlint'
      end
      options.other = options.other.map { |name, value| [ "-#{name}", value.to_s ] }.flatten if Hash === options.other
      args + Array(options.other)
    end

  end
=end


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

    def initialize(*args) #:nodoc:
      super
      parent = Project.task_in_parent_project(name)
      @options = parent && parent.respond_to?(:options) && parent.options.clone || OpenStruct.new
      @sources = []
      @dependencies = []

      project = Project.project_from_task(self)
      @compiler = Compiler.identify(project)
      compiler.configure(self, project) if compiler

      enhance do |task|
        unless target.nil? || sources.empty?
          raise "No compiler selected and can't determine default compiler to use" unless compiler
          mkpath target.to_s, :verbose=>false
          compiler.compile(sources, target, dependencies, options, task.name)
          # By touching the target we let other tasks know we did something,
          # and also prevent recompiling again for dependencies.
          touch target.to_s, :verbose=>false
        end
      end
    end

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
      path = File.expand_path(path.to_s)
      @target = file(path).enhance([self]) unless @target && @target.to_s == path
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
      select args.first unless args.empty?
      self
    end

    # Returns the compiler if known.  The compiler is either automatically selected
    # based on existing source directories (e.g. src/main/java), or by requesting
    # a specific compiler (see #using).
    attr_reader :compiler

    def select(compiler) #:nodoc:
      raise "#{compiler.name} already selected for this project" if @compiler
      @compiler = Compiler.select(compiler.to_s)
      self
    end

    def timestamp #:nodoc:
      # If we compiled successfully, then the target directory reflects that.
      # If we didn't, see needed?
      target ? target.timestamp : Rake::EARLY
    end

    def needed? #:nodoc:
      return false if source_files.empty?
      return true unless File.exist?(target.to_s)
      return true if source_files.any? { |j, c| !File.exist?(c) || File.stat(j).mtime > File.stat(c).mtime }
      oldest = source_files.map { |j, c| File.stat(c).mtime }.min
      return dependencies.any? { |path| application[path].timestamp > oldest }
    end

    def invoke_prerequisites(args, chain) #:nodoc:
      @prerequisites |= dependencies + sources
      super
    end

  private

    # Returns the files to compile. This list is derived from the list of sources,
    # expanding directories into files, and includes only source files that are
    # newer than the corresponding class file. Includes all files if one or more
    # dependency has been updated.
    def source_files
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

end
