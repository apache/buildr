require 'buildr/core/doc'
require 'buildr/scala/compiler'   # ensure Scala dependencies are ready

module Buildr
  module Doc
    class Scaladoc < Base
      specify :language => :scala, :source_ext => 'scala'

      def generate(sources, target, options = {})
        cmd_args = [ '-d', target, Buildr.application.options.trace ? '-verbose' : '' ]
        options.reject { |key, value| [:sourcepath, :classpath].include?(key) }.
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
          Array(options[option]).flatten.tap do |paths|
            cmd_args << "-#{option}" << paths.flatten.map(&:to_s).join(File::PATH_SEPARATOR) unless paths.empty?
          end
        end
        cmd_args += sources.flatten.uniq
        unless Buildr.application.options.dryrun
          info "Generating Scaladoc for #{project.name}"
          trace (['scaladoc'] + cmd_args).join(' ')
          Java.load
          Java.scala.tools.nsc.ScalaDoc.main(cmd_args.to_java(Java.java.lang.String)) == 0 or
            fail 'Failed to generate Scaladocs, see errors above'
        end
      end
    end

    class VScaladoc < Base
      VERSION = '1.2-SNAPSHOT'
      Buildr.repositories.remote << 'http://scala-tools.org/repo-snapshots'

      class << self
        def dependencies
          [ "org.scala-tools:vscaladoc:jar:#{VERSION}" ]
        end
      end

      Java.classpath << dependencies

      specify :language => :scala, :source_ext => 'scala'

      def generate(sources, target, options = {})
        cmd_args = [ '-d', target, (Buildr.application.options.trace ? '-verbose' : ''),
          '-sourcepath', project.compile.sources.join(File::PATH_SEPARATOR) ]
        options.reject { |key, value| [:sourcepath, :classpath].include?(key) }.
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
          Array(options[option]).flatten.tap do |paths|
            cmd_args << "-#{option}" << paths.flatten.map(&:to_s).join(File::PATH_SEPARATOR) unless paths.empty?
          end
        end
        cmd_args += sources.flatten.uniq
        unless Buildr.application.options.dryrun
          info "Generating VScaladoc for #{project.name}"
          trace (['vscaladoc'] + cmd_args).join(' ')
          Java.load
          Java.org.scala_tools.vscaladoc.Main.main(cmd_args.to_java(Java.java.lang.String)) == 0 or
            fail 'Failed to generate VScaladocs, see errors above'
        end
      end
    end
  end
end

Buildr::Doc.engines << Buildr::Doc::Scaladoc
Buildr::Doc.engines << Buildr::Doc::VScaladoc
