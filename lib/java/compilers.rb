require "core/project"
require "core/common"
require "core/compile"
require "java/artifact"
require "java/java"

module Buildr
  module Compiler

    # Javac compiler:
    #   compile.using(:javac)
    # Used by default if .java files are found in the src/main/java directory (or src/test/java)
    # and sets the target directory to target/classes (or target/test/classes).
    #
    # Accepts the following options:
    # * :wranings -- Issue warnings when compiling.  True when running in verbose mode.
    # * :debug    -- Generates bytecode with debugging information.  Set from the debug environment
    #                variable/global option.
    # * :deprecation -- If true, shows deprecation messages.  False by default.
    # * :source      -- Source code compatibility.
    # * :target      -- Bytecode compatibility.
    # * :lint        -- Lint option is one of true, false (default), name (e.g. 'cast') or array.
    # * :other       -- Array of options passed to the compiler (e.g. '-implicit:none')
    class Javac < Base
      
      OPTIONS = [:warnings, :debug, :deprecation, :source, :target, :lint, :other]

      def initialize #:nodoc:
        super :language=>:java, :target_path=>'classes', :target_ext=>'.class', :packaging=>:jar
      end

      def configure(task, source, target) #:nodoc:
        super
        update_options_from_parent! task, OPTIONS
        task.options.warnings ||= verbose
        task.options.deprecation ||= false
        task.options.lint ||= false
        task.options.debug ||= Buildr.options.debug
      end

      def compile(files, task) #:nodoc:
        check_options task, OPTIONS
        ::Buildr::Java.javac files, :sourcepath=>task.sources.select { |source| File.directory?(source) },
          :classpath=>task.dependencies, :output=>task.target, :javac_args=>javac_args_from(task.options)
      end

    private

      def javac_args_from(options) #:nodoc:
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
        args + Array(options.other)
      end

    end

  end


  # Methods added to Project for creating JavaDoc documentation.
  module Javadoc

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
          Java.javadoc source_files, options.merge(:classpath=>classpath, :sourcepath=>sourcepath,
            :name=>name, :output=>File.expand_path(target.to_s))
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
        @target = file(path.to_s).enhance([self]) unless @target && @target.to_s == path.to_s
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
            self.enhance source.prerequisites
            self.include source.compile.sources
            self.with source.compile.dependencies 
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


    include Extension

    first_time do
      desc 'Create the Javadocs for this project'
      Project.local_task('javadoc')
    end

    before_define do |project|
      JavadocTask.define_task('javadoc').tap do |javadoc|
        javadoc.into project.path_to(:target, :javadoc)
        javadoc.using :windowtitle=>project.comment || project.name
      end
    end

    after_define do |project|
      project.javadoc.from project
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
    #   javadoc projects('myapp:foo', 'myapp:bar').using(:windowtitle=>'Docs for foo and bar')
    def javadoc(*sources, &block)
      task('javadoc').from(*sources).enhance &block
    end

  end


  # Methods added to Project to support the Java Annotation Processor.
  module Apt

    # :call-seq:
    #   apt(*sources) => task
    #
    # Returns a task that will use Java#apt to generate source files in target/generated/apt,
    # from all the source directories passed as arguments. Uses the compile.sources list if
    # on arguments supplied.
    #
    # For example:
    #
    def apt(*sources)
      sources = compile.sources if sources.empty?
      file(path_to(:target, "generated/apt")=>sources) do |task|
        Java.apt(sources.map(&:to_s) - [task.name], :output=>task.name,
          :classpath=>compile.dependencies, :source=>compile.options.source)
      end
    end

  end

end

Buildr::Compiler.add Buildr::Compiler::Javac
class Buildr::Project
  include Buildr::Javadoc
  include Buildr::Apt
end
