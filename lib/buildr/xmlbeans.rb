require "java/java"
require "java/ant"

module Buildr

  # Provides XMLBeans schema compiler. Require explicitly using <code>require "buildr/xmlbeans"</code>.
  module XMLBeans

    STAX = "stax:stax-api:jar:1.0"
    XMLBEANS = "org.apache.xmlbeans:xmlbeans:jar:2.3.0"
    REQUIRES = [ STAX, XMLBEANS ]

    class << self

      def compile(*args)
        options = Hash === args.last ? args.pop : {}
        options[:verbose] ||= Rake.application.options.trace || false
        rake_check_options options, :verbose, :noop, :javasource, :jar, :compile, :output, :xsb
        puts "Running XMLBeans schema compiler" if verbose
        Buildr.ant "xmlbeans" do |ant|
          ant.taskdef :name=>"xmlbeans", :classname=>"org.apache.xmlbeans.impl.tool.XMLBean",
            :classpath=>requires.join(File::PATH_SEPARATOR)
          ant.xmlbeans :srconly=>"true", :srcgendir=>options[:output].to_s, :classgendir=>options[:output].to_s, 
            :javasource=>options[:javasource] do
            args.flatten.each { |file| ant.fileset File.directory?(file) ? { :dir=>file } : { :file=>file } }
          end
        end
        # Touch paths to let other tasks know there's an update.
        touch options[:output].to_s, :verbose=>false
      end

    private

      def requires()
        @requires ||= Buildr.artifacts(REQUIRES).each { |artifact| artifact.invoke }.map(&:to_s)
      end
    
    end

    def compile_xml_beans(*args)
      # Run whenever XSD file changes, but typically we're given an directory of XSD files, or even file patterns
      # (the last FileList is there to deal with things like *.xsdconfig).
      files = args.flatten.map { |file| File.directory?(file) ? FileList["#{file}/*.xsd"] : FileList[file] }.flatten
      # Generate sources and add them to the compile task.
      generated = file(path_to(:target, "generated/xmlbeans")=>files) do |task|
        XMLBeans.compile args.flatten, :output=>task.name,
          :javasource=>compile.options.source, :xsb=>compile.target
      end
      compile.from(generated).with(STAX, XMLBEANS)
      # Once compiled, we need to copy the generated XSB/XSD and one (magical?) class file
      # into the target directory, or the rest is useless.
      compile do |task|
        verbose(false) do
          base = Pathname.new(generated.to_s)
          FileList["#{base}/**/*.{class,xsb,xsd}"].each do |file|
            target = File.join(compile.target.to_s, Pathname.new(file).relative_path_from(base))
            mkpath File.dirname(target) ; cp file, target
          end
        end
      end
    end

  end

  class Project
    include XMLBeans
  end
end
