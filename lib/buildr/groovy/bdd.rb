module Buildr::Groovy

  # EasyB is a Groovy based BDD framework.
  # To use in your project:
  #
  #   test.using :easyb
  # 
  # This framework will search in your project for:
  #   src/spec/groovy/**/*Story.groovy
  #   src/spec/groovy/**/*Behavior.groovy
  #
  # Support the following options:
  # * :format -- Report format :txt or :xml, default is :txt
  # * :properties -- Hash of properties passed to the test suite.
  # * :java_args -- Arguments passed to the JVM.
  class EasyB < TestFramework::JavaBDD
    @lang = :groovy
    @bdd_dir = :spec

    VERSION = "0.7" unless const_defined?(:VERSION)
    TESTS_PATTERN = [ /(Story|Behavior).groovy$/ ]
    OPTIONS = [:format, :properties, :java_args]

    class << self
      def version
        Buildr.settings.build['jbehave'] || VERSION
      end

      def dependencies
        @dependencies ||= ["org.easyb:easyb:jar:#{version}",
          'org.codehaus.groovy:groovy:jar:1.5.3','asm:asm:jar:2.2.3',
          'commons-cli:commons-cli:jar:1.0','antlr:antlr:jar:2.7.7']
      end

      def applies_to?(project) #:nodoc:
        %w{
          **/*Behaviour.groovy **/*Behavior.groovy **/*Story.groovy
        }.any? { |glob| !Dir[project.path_to(:source, bdd_dir, lang, glob)].empty? }
      end

    private
      def const_missing(const)
        return super unless const == :REQUIRES # TODO: remove in 1.5
        Buildr.application.deprecated "Please use JBehave.dependencies/.version instead of JBehave::REQUIRES/VERSION"
        dependencies
      end
    end

    def tests(dependencies) #:nodoc:
      Dir[task.project.path_to(:source, bdd_dir, lang, "**/*.groovy")].
        select { |name| TESTS_PATTERN.any? { |pat| pat === name } }
    end

    def run(tests, dependencies) #:nodoc:
      options = { :format => :txt }.merge(self.options).only(*OPTIONS)
    
      if :txt == options[:format]
        easyb_format, ext = 'txtstory', '.txt'
      elsif :xml == options[:format]
        easyb_format, ext = 'xmlbehavior', '.xml'
      else
        raise "Invalid format #{options[:format]} expected one of :txt :xml"
      end
    
      cmd_args = [ 'org.disco.easyb.SpecificationRunner' ]
      cmd_options = { :properties => options[:properties],
                      :java_args => options[:java_args],
                      :classpath => dependencies }

      tests.inject([]) do |passed, test|
        name = test.sub(/.*?groovy[\/\\]/, '').pathmap('%X')
        report = File.join(task.report_to.to_s, name + ext)
        mkpath report.pathmap('%d'), :verbose => false
        begin
          Java::Commands.java cmd_args,
             "-#{easyb_format}", report,
             test, cmd_options.merge(:name => name)
        rescue => e
          passed
        else
          passed << test
        end
      end
    end
  
  end # EasyB
  
end

Buildr::TestFramework << Buildr::Groovy::EasyB