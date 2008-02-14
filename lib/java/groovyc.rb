module Buildr
  module Compiler
    # Groovyc compiler:
    #  compile.using(:groovyc)
    #
    # You need to require 'java/groovyc' if you need to use this compiler.
    #
    # Used by default if .groovy files are found in the src/main/groovy directory (or src/test/groovy)
    # and sets the target directory to target/classes (or target/test/classes).
    #
    # Groovyc is a joint compiler, this means that when selected for a project, this compiler is used
    # to compile both groovy and java sources. It's recommended that Groovy sources are placed in the
    # src/main/groovy directory, even though this compiler also looks in src/main/java
    #
    # Groovyc accepts the following options:
    #
    # * :encoding          -- Encoding of source files
    # * :verbose           -- Asks the compiler for verbose output, true when running in verbose mode.
    # * :fork              -- Whether to execute groovyc using a spawned instance of the JVM; defaults to no
    # * :memoryInitialSize -- The initial size of the memory for the underlying VM, if using fork mode; ignored otherwise. 
    #                                     Defaults to the standard VM memory setting. (Examples: 83886080, 81920k, or 80m)
    # * :memoryMaximumSize -- The maximum size of the memory for the underlying VM, if using fork mode; ignored otherwise. 
    #                                     Defaults to the standard VM memory setting. (Examples: 83886080, 81920k, or 80m)
    # * :listfiles         -- Indicates whether the source files to be compiled will be listed; defaults to no
    # * :stacktrace        -- If true each compile error message will contain a stacktrace
    # * :warnings          -- Issue warnings when compiling.  True when running in verbose mode.
    # * :debug             -- Generates bytecode with debugging information.  Set from the debug
    #                                     environment variable/global option.
    # * :deprecation       -- If true, shows deprecation messages.  False by default.
    # * :optimise          -- Generates faster bytecode by applying optimisations to the program.
    # * :source            -- Source code compatibility.
    # * :target            -- Bytecode compatibility.
    # * :javac             -- Hash of options passed to the ant javac task
    class Groovyc < Base

      # Which groovy version to use?
      VERSION = "1.5.3" unless const_defined?('VERSION')

      REQUIRES = Buildr.struct(
        :groovy => "org.codehaus.groovy:groovy:jar:#{VERSION}",
        :commons_cli => 'commons-cli:commons-cli:jar:1.0',
        :asm => 'asm:asm:jar:2.2.3',
        :antlr => 'antlr:antlr:jar:2.7.7'
      ) unless const_defined?('REQUIRES')
      
      ANT_TASK = 'org.codehaus.groovy.ant.Groovyc'
      GROOVYC_OPTIONS = [:encoding, :verbose, :fork, :memoryInitialSize, :memoryMaximumSize, :listfiles, :stacktrace]
      JAVAC_OPTIONS = [:optimise, :warnings, :debug, :deprecation, :source, :target, :javac]
      OPTIONS = GROOVYC_OPTIONS + JAVAC_OPTIONS

      class << self
        def dependencies #:nodoc:
          Buildr.artifacts(REQUIRES)
        end

        def applies_to?(project, task) #:nodoc:
          paths = task.sources + [sources].flatten.map { |src| Array(project.path_to(:source, task.usage, src.to_sym)) }
          paths.flatten!
          # Just select if we find .groovy files
          paths.any? { |path| !Dir["#{path}/**/*.groovy"].empty? }
        end
      end
      
      Java.classpath << dependencies
      
      specify :language => [:groovy, :java], :target => 'classes', :target_ext => 'class', :packaging => :jar

      def initialize(project, options) #:nodoc:
        super
        options[:debug] = Buildr.options.debug if options[:debug].nil?
        options[:deprecation] ||= false
        options[:optimise] ||= false
        options[:verbose] ||= Rake.application.options.trace if options[:verbose].nil?
        options[:warnings] = verbose if options[:warnings].nil?
        options[:javac] = OpenObject.new if options[:javac].nil?
      end

      # http://groovy.codehaus.org/The+groovyc+Ant+Task
      def compile(sources, target, dependencies) #:nodoc:
        return if Rake.application.options.dryrun
        Buildr.ant 'groovyc' do |ant|
          classpath = dependencies | self.class.dependencies.map(&:to_s)
          ant.taskdef :name => 'groovyc', :classname => ANT_TASK, :classpath => classpath.join(File::PATH_SEPARATOR)
          ant.groovyc groovyc_options(sources, target) do
            sources.each { |src| ant.src :path => src }
            ant.classpath do
              classpath.each { |dep| ant.pathelement :path => dep }
            end
            ant.javac(javac_options)
          end
        end
      end

     private 
      def groovyc_options(sources, target)
        check_options options, OPTIONS
        groovyc_options = options.only(*GROOVYC_OPTIONS)
        groovyc_options[:destdir] = File.expand_path(target)
        groovyc_options
      end

      def javac_options
        check_options options, OPTIONS
        javac_options = options.only(*JAVAC_OPTIONS)
        javac_options[:optimize] = (javac_options.delete(:optimise) || false)
        javac_options[:nowarn] = (javac_options.delete(:warnings) || verbose).to_s !~ /^(true|yes|on)$/i
        other = javac_options.delete(:javac) || {}
        javac_options.merge!(other)
        javac_options
      end
      
    end
  end
end

Buildr::Compiler.compilers.unshift Buildr::Compiler::Groovyc
