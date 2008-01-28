require "java/java"

module Buildr
  # Provides JavaCC compile tasks. Require explicitly using <code>require "buildr/javacc"</code>.
  module JavaCC

    REQUIRES = [ "net.java.dev.javacc:javacc:jar:4.0", "net.java.dev.javacc:javacc:jar:4.0" ]

    Java.classpath << REQUIRES

    class << self

      def javacc(*args)
        options = Hash === args.last ? args.pop : {}
        rake_check_options options, :output

        args = args.flatten.map(&:to_s).collect { |f| File.directory?(f) ? FileList[f + "/**/*.jj"] : f }.flatten
        args.unshift "-OUTPUT_DIRECTORY=#{options[:output]}" if options[:output]
        Java.load
        Java.org.javacc.parser.Main.mainProgram(args.to_java(Java.java.lang.String)) == 0 or
          fail "Failed to run JavaCC, see errors above."
      end

      def jjtree(*args)
        options = Hash === args.last ? args.pop : {}
        rake_check_options options, :output, :build_node_files

        args = args.flatten.map(&:to_s).collect { |f| File.directory?(f) ? FileList[f + "**/*.jjt"] : f }.flatten
        args.unshift "-OUTPUT_DIRECTORY=#{options[:output]}" if options[:output]
        args.unshift "-BUILD_NODE_FILES=#{options[:build_node_files] || false}"
        Java.load
        Java.org.javacc.jjtree.JJTree.new.main(args.to_java(Java.java.lang.String)) == 0 or
          fail "Failed to run JJTree, see errors above."
      end

    end

    def javacc(*args)
      if Hash === args.last
        options = args.pop 
        in_package = options[:in_package].split(".")
      else
        in_package = []
      end
      file(path_to(:target, :generated, :javacc)=>args.flatten) do |task|
        JavaCC.javacc task.prerequisites, :output=>File.join(task.name, in_package)
      end         
    end

    def jjtree(*args)
      if Hash === args.last
        options = args.pop 
        in_package = options[:in_package].split(".")
        build_node_files = options[:build_node_files]
      else
        in_package = []
      end
      file(path_to(:target, :generated, :jjtree)=>args.flatten) do |task|
        JavaCC.jjtree task.prerequisites, :output=>File.join(task.name, in_package), :build_node_files=>build_node_files
      end         
    end

  end

  class Project
    include JavaCC
  end
end
