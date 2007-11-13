module Buildr

  # Addes the <code>jdepend:swing</code>, <code>jdepend:text</code> and <code>jdepend:xml</code> tasks.
  # Require explicitly using <code>require "buildr/jdepend"</code>.
  module Jdepend

    REQUIRES = ["jdepend:jdepend:jar:2.9.1"]

    class << self

      def requires()
        @requires ||= Buildr.artifacts(REQUIRES).each(&:invoke).map(&:to_s)
      end

      def paths()
        Project.projects.map(&:compile).each(&:invoke).map(&:target).map(&:to_s).select { |path| File.exist?(path) }
      end

    end

    namespace "jdepend" do

      desc "Runs JDepend on all your projects (Swing UI)"
      task "swing" do
        Buildr.java "jdepend.swingui.JDepend", paths, :classpath=>requires, :name=>"JDepend"
      end

      desc "Runs JDepend on all your projects (Text UI)"
      task "text" do
        Buildr.java "jdepend.textui.JDepend", paths, :classpath=>requires, :name=>"JDepend"
      end

      desc "Runs JDepend on all your projects (XML output to jdepend.xml)"
      task "xml" do
        Buildr.java "jdepend.xmlui.JDepend", "-file", "jdepend.xml", paths, :classpath=>requires, :name=>"JDepend"
        puts "Created jdepend.xml"
      end
    end
  end
end
