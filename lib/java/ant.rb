require 'core/project'
require 'java/java'
require 'antwrap'
require 'core/help'


module Buildr
  module Ant

    # Which version of Ant we're using by default.
    VERSION = '1.7.0' unless const_defined?('VERSION')

    # Libraries used by Ant.
    REQUIRES = [ "org.apache.ant:ant:jar:#{VERSION}", "org.apache.ant:ant-launcher:jar:#{VERSION}", 'xerces:xercesImpl:jar:2.6.2' ]
    Java.classpath << REQUIRES

    # :call-seq:
    #   ant(name) { |AntProject| ... } => AntProject
    #
    # Creates a new AntProject with the specified name, yield to the block for defining various
    # Ant tasks, and executes each task as it's defined.
    #
    # For example:
    #   ant("hibernatedoclet') do |doclet|
    #     doclet.taskdef :name=>'hibernatedoclet',
    #       :classname=>'xdoclet.modules.hibernate.HibernateDocletTask', :classpath=>DOCLET
    #     doclet.hibernatedoclet :destdir=>dest_dir, :force=>'true' do
    #       hibernate :version=>'3.0'
    #       fileset :dir=>source, :includes=>'**/*.java'
    #     end
    #   end
    def ant(name, &block)
      options = { :name=>name, :basedir=>Dir.pwd, :declarative=>true }
      options.merge!(:logger=> Logger.new(STDOUT), :loglevel=> Logger::DEBUG) if Rake.application.options.trace
      Java.load
      Antwrap::AntProject.new(options).tap do |project|
        # Set Ant logging level to debug (--trace), info (default) or error only (--quiet).
        project.project.getBuildListeners().get(0).
          setMessageOutputLevel((Rake.application.options.trace && 4) || (verbose && 2) || 0)
        yield project if block_given?
      end
    end

  end

  include Ant

  Buildr.help do
    Java.load
    "\nUsing Java #{ENV_JAVA['java.version']}, Ant #{Ant::VERSION}."
  end

end
