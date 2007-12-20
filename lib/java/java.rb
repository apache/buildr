require "rjb" if RUBY_PLATFORM != 'java'
require "java" if RUBY_PLATFORM == 'java'
require "core/project"

module Buildr

  # Base module for all things Java.
  module Java

    # Options accepted by #java and other methods here.
    JAVA_OPTIONS = [ :verbose, :classpath, :name, :java_args, :properties ]

    # Returned by Java#wrapper, you can use this object to set the classpath, specify blocks to be invoked
    # after loading RJB, and load RJB itself.
    #
    # RJB can be loaded exactly once, and once loaded, you cannot change its classpath. Of course you can
    # call libraries that manage their own classpath, but the lazy way is to just tell RJB of all the
    # classpath dependencies you need in advance, before loading it.
    #
    # For that reason, you should not load RJB until the moment you need it. You can call #load or call
    # Java#wrapper with a block. For the same reason, you may need to specify code to execute when loading
    # (see #setup).
    #
    # JRuby doesn't have the above limitation, but uses the same API regardless.
    class JavaWrapper #:nodoc:

      include Singleton

      def initialize() #:nodoc:
        @classpath = [Java.tools_jar].compact
        if Java.jruby?
          # in order to get a complete picture, we need to add a few jars to the list.
          @classpath += java.lang.System.getProperty('java.class.path').split(':').compact
        end
        @setup = []

        setup do
          setup do
            cp = Buildr.artifacts(@classpath).map(&:to_s)
            cp.each { |path| file(path).invoke }

            if Java.jruby?
              cp.each do |jlib|
                require jlib
              end
            else
              ::Rjb.load cp.join(File::PATH_SEPARATOR), Buildr.options.java_args.flatten
            end
          end
        end
      end

      attr_accessor :classpath

      def setup(&block)
        @setup << block
        self
      end
      
      def onload(&block)
        warn_deprecated "use setup { |wrapper| ... } instead"
        setup &block
      end

      def load(&block)
        @setup.each { |block| block.call self }
        @setup.clear
      end

      def import(jlib)
        if Java.jruby?
          ::Java.instance_eval(jlib)
        else
          ::Rjb.import jlib
        end
      end

      def method_missing(sym, *args, &block) #:nodoc:
        # these aren't the same, but depending on method_missing while
        # supporting two unrelated systems is asking for trouble anyways.
        if Java.jruby?
          ::Java.send sym, *args, &block
        else
          ::Rjb.send sym, *args, &block
        end
      end
    end
    
    class << self

      # :call-seq:
      #   version() => string
      #
      # Returns the version number of the JVM.
      #
      # For example:
      #   puts Java.version
      #   => 1.5.0_10
      def version()
        @version ||= Java.wrapper { |jw| jw.import("java.lang.System").getProperty("java.version") }
      end

      # :call-seq:
      #   tools_jar() => path
      #
      # Returns a path to tools.jar. On OS/X which has not tools.jar, returns an empty array,
      # on all other platforms, fails if it doesn't find tools.jar.
      def tools_jar()
        return [] if darwin?
        @tools ||= [File.join(home, "lib/tools.jar")] or raise "I need tools.jar to compile, can't find it in #{home}/lib"
      end

      # :call-seq:
      #   home() => path
      #
      # Returns JAVA_HOME, fails if JAVA_HOME not set.
      def home()
        @home ||= ENV["JAVA_HOME"] or fail "Are we forgetting something? JAVA_HOME not set."
      end

      # :call-seq:
      #   java(class, *args, options?)
      #
      # Runs Java with the specified arguments.
      #
      # The last argument may be a Hash with additional options:
      # * :classpath -- One or more file names, tasks or artifact specifications.
      #   These are all expanded into artifacts, and all tasks are invoked.
      # * :java_args -- Any additional arguments to pass (e.g. -hotspot, -xms)
      # * :properties -- Hash of system properties (e.g. "path"=>base_dir).
      # * :name -- Shows this name, otherwise shows the first argument (the class name).
      # * :verbose -- If true, prints the command and all its argument.
      def java(*args, &block)
        options = Hash === args.last ? args.pop : {}
        options[:verbose] ||= Rake.application.options.trace || false
        rake_check_options options, *JAVA_OPTIONS

        name = options[:name] || "java #{args.first}"
        cmd_args = [path_to_bin("java")]
        classpath = classpath_from(options)
        cmd_args << "-cp" << classpath.join(File::PATH_SEPARATOR) unless classpath.empty?
        options[:properties].each { |k, v| cmd_args << "-D#{k}=#{v}" } if options[:properties]
        cmd_args += (options[:java_args] || Buildr.options.java_args).flatten
        cmd_args += args.flatten.compact
        unless Rake.application.options.dryrun
          puts "Running #{name}" if verbose
          block = lambda { |ok, res| fail "Failed to execute #{name}, see errors above" unless ok } unless block
          puts cmd_args.join(" ") if Rake.application.options.trace
          system(cmd_args.map { |arg| %Q{"#{arg}"} }.join(" ")).tap do |ok|
            block.call ok, $?
          end
        end
      end

      # :call-seq:
      #   apt(*files, options)
      #
      # Runs Apt with the specified arguments.
      #
      # The last argument may be a Hash with additional options:
      # * :compile -- If true, compile source files to class files.
      # * :source -- Specifies source compatibility with a given JVM release.
      # * :output -- Directory where to place the generated source files, or the
      #   generated class files when compiling.
      # * :classpath -- One or more file names, tasks or artifact specifications.
      #   These are all expanded into artifacts, and all tasks are invoked.
      def apt(*args)
        options = Hash === args.last ? args.pop : {}
        rake_check_options options, :compile, :source, :output, :classpath

        files = args.flatten.map(&:to_s).
          collect { |arg| File.directory?(arg) ? FileList["#{arg}/**/*.java"] : arg }.flatten
        cmd_args = [ Rake.application.options.trace ? "-verbose" : "-nowarn" ]
        if options[:compile]
          cmd_args << "-d" << options[:output].to_s
        else
          cmd_args << "-nocompile" << "-s" << options[:output].to_s
        end
        cmd_args << "-source" << options[:source] if options[:source]
        classpath = classpath_from(options)
        cmd_args << "-cp" << classpath.join(File::PATH_SEPARATOR) unless classpath.empty?
        cmd_args += files
        unless Rake.application.options.dryrun
          puts "Running apt" if verbose
          puts (["apt"] + cmd_args).join(" ") if Rake.application.options.trace
          Java.wrapper do |jw|
            cmd_args = cmd_args.to_java_array(::Java.java.lang.String) if Java.jruby?
            jw.import("com.sun.tools.apt.Main").process(cmd_args) == 0 or
              fail "Failed to process annotations, see errors above"
          end
        end
      end

      # :call-seq:
      #   javac(*files, options)
      #
      # Runs Javac with the specified arguments.
      #
      # The last argument may be a Hash with additional options:
      # * :output -- Target directory for all compiled class files.
      # * :classpath -- One or more file names, tasks or artifact specifications.
      #   These are all expanded into artifacts, and all tasks are invoked.
      # * :sourcepath -- Additional source paths to use.
      # * :javac_args -- Any additional arguments to pass (e.g. -extdirs, -encoding)
      # * :name -- Shows this name, otherwise shows the working directory.
      def javac(*args)
        options = Hash === args.last ? args.pop : {}
        rake_check_options options, :classpath, :sourcepath, :output, :javac_args, :name

        files = args.flatten.each { |f| f.invoke if f.respond_to?(:invoke) }.map(&:to_s).
          collect { |arg| File.directory?(arg) ? FileList["#{arg}/**/*.java"] : arg }.flatten
        name = options[:name] || Dir.pwd

        cmd_args = []
        classpath = classpath_from(options)
        cmd_args << "-cp" << classpath.join(File::PATH_SEPARATOR) unless classpath.empty?
        cmd_args << "-sourcepath" << options[:sourcepath].join(File::PATH_SEPARATOR) if options[:sourcepath]
        cmd_args << "-d" << options[:output].to_s if options[:output]
        cmd_args += options[:javac_args].flatten if options[:javac_args]
        cmd_args += files
        unless Rake.application.options.dryrun
          puts "Compiling #{files.size} source files in #{name}" if verbose
          puts (["javac"] + cmd_args).join(" ") if Rake.application.options.trace
          Java.wrapper do |jw|
            cmd_args = cmd_args.to_java_array(::Java.java.lang.String) if Java.jruby?
            jw.import("com.sun.tools.javac.Main").compile(cmd_args) == 0 or 
              fail "Failed to compile, see errors above"
          end
        end
      end

      # :call-seq:
      #   javadoc(*files, options)
      #
      # Runs Javadocs with the specified files and options.
      #
      # This method accepts the following special options:
      # * :output -- The output directory
      # * :classpath -- Array of classpath dependencies.
      # * :sourcepath -- Array of sourcepaths (paths or tasks).
      # * :name -- Shows this name, otherwise shows the working directory.
      #
      # All other options are passed to Javadoc as following:
      # * true -- As is, for example, :author=>true becomes -author
      # * false -- Prefixed, for example, :index=>false becomes -noindex
      # * string -- Option with value, for example, :windowtitle=>"My project" becomes -windowtitle "My project"
      # * array -- Option with set of values separated by spaces.
      def javadoc(*args)
        options = Hash === args.last ? args.pop : {}

        cmd_args = [ "-d", options[:output], Rake.application.options.trace ? "-verbose" : "-quiet" ]
        options.reject { |key, value| [:output, :name, :sourcepath, :classpath].include?(key) }.
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
          options[option].to_a.flatten.tap do |paths|
            cmd_args << "-#{option}" << paths.flatten.map(&:to_s).join(File::PATH_SEPARATOR) unless paths.empty?
          end
        end
        cmd_args += args.flatten.uniq
        name = options[:name] || Dir.pwd
        unless Rake.application.options.dryrun
          puts "Generating Javadoc for #{name}" if verbose
          puts (["javadoc"] + cmd_args).join(" ") if Rake.application.options.trace
          Java.wrapper do |jw|
            cmd_args = cmd_args.to_java_array(::Java.java.lang.String) if Java.jruby?
            jw.import("com.sun.tools.javadoc.Main").execute(cmd_args) == 0 or
              fail "Failed to generate Javadocs, see errors above"
          end
        end
      end

      # :call-seq:
      #   junit(*classes, options) => [ passed, failed ]
      #
      # Runs JUnit test cases from the specified classes. Returns an array with two lists,
      # one containing the names of all classes that passes, the other containing the names
      # of all classes that failed.
      #
      # The last argument may be a Hash with additional options:
      # * :classpath -- One or more file names, tasks or artifact specifications.
      #   These are all expanded into artifacts, and all tasks are invoked.
      # * :properties -- Hash of system properties (e.g. "path"=>base_dir).
      # * :java_args -- Any additional arguments to pass (e.g. -hotspot, -xms)
      # * :verbose -- If true, prints the command and all its argument.
      #
      # *Deprecated:* Please use JUnitTask instead.Use the test task to run JUnit and other test frameworks.
      def junit(*args)
        warn_deprecated "Use the test task to run JUnit and other test frameworks"
        options = Hash === args.last ? args.pop : {}
        options[:verbose] ||= Rake.application.options.trace || false
        rake_check_options options, :verbose, :classpath, :properties, :java_args

        classpath = classpath_from(options) + JUnitTask::requires
        tests = args.flatten
        failed = tests.inject([]) do |failed, test|
          begin
            java "junit.textui.TestRunner", test, :classpath=>classpath, :properties=>options[:properties],
              :name=>"#{test}", :verbose=>options[:verbose], :java_args=>options[:java_args]
            failed
          rescue
            failed << test
          end
        end
        [ tests - failed, failed ]
      end


      # :call-seq:
      #   wrapper() => JavaWrapper
      #   wrapper() { ... }
      #
      # This method can be used in two ways. Without a block, returns the
      # JavaWrapper object which you can use to configure the classpath or call
      # other methods. With a block, loads RJB or sets up JRuby and yields to
      # the block, returning its result.
      #
      # For example:
      #   # Add class path dependency.
      #   Java.wrapper.classpath << REQUIRES
      #   # Require AntWrap when loading RJB/JRuby.
      #   Java.wrapper.setup { require "antwrap" }
      #
      #  def execute(name, options)
      #    options = options.merge(:name=>name, :base_dir=>Dir.pwd, :declarative=>true)
      #    # Load RJB/JRuby and run AntWrap.
      #    Java.wrapper { AntProject.new(options) }
      #  end
      def wrapper()
        if block_given?
          JavaWrapper.instance.load
          yield JavaWrapper.instance
        else
          JavaWrapper.instance
        end
      end

      def rjb(&block)
        warn_deprecated "please use Java.wrapper() instead"
        wrapper &block
      end

      # :call-seq:
      #   path_to_bin(cmd?) => path
      #
      # Returns the path to the specified Java command (with no argument to java itself).
      def path_to_bin(name = "java")
        File.join(home, "bin", name)
      end

      # return true if we a running on c-ruby and must use rjb
      def rjb?; RUBY_PLATFORM != "java"; end
      # return true if we are running on jruby
      def jruby?; RUBY_PLATFORM == "java"; end

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

      def darwin?() #:nodoc:
        RUBY_PLATFORM =~ /darwin/i
      end

    end

    # See Java#java.
    def java(*args)
      Java.java(*args)
    end

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
          :classpath=>compile.classpath, :source=>compile.options.source)
      end
    end

  end

  include Java

  class Options

    # :call-seq:
    #   java_args => array
    #
    # Returns the Java arguments.
    def java_args()
      @java_args ||= (ENV["JAVA_OPTS"] || ENV["JAVA_OPTIONS"] || "").split(" ")
    end

    # :call-seq:
    #   java_args = array|string|nil
    #
    # Sets the Java arguments. These arguments are used when creating a JVM, including for use with RJB
    # for most tasks (e.g. Ant, compile) and when forking a separate JVM (e.g. JUnit tests). You can also
    # use the JAVA_OPTS environment variable.
    #
    # For example:
    #   options.java_args = "-verbose"
    # Or:
    #   $ set JAVA_OPTS = "-Xms1g"
    #   $ buildr
    def java_args=(args)
      args = args.split if String === args
      @java_args = args.to_a
    end

  end

end


if Buildr::Java.jruby?
  
  # Convert a RubyArray to a Java Object[] array of the specified element_type
  class Array #:nodoc:
    def to_java_array(element_type)
      java_array = ::Java.java.lang.reflect.Array.newInstance(element_type, self.size)
      self.each_index { |i| java_array[i] = self[i] }
      return java_array
    end
  end

end
