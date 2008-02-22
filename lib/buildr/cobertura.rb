# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.


module Buildr

  # Addes the <code>cobertura:html</code> and <code>cobertura:xml</code> tasks.
  # Require explicitly using <code>require "buildr/cobertura"</code>.
  module Cobertura

    class << self

      REQUIRES = ["net.sourceforge.cobertura:cobertura:jar:1.9", "log4j:log4j:jar:1.2.9",
        "asm:asm:jar:2.2.1", "asm:asm-tree:jar:2.2.1", "oro:oro:jar:2.0.8"]

      def requires()
        @requires ||= Buildr.artifacts(REQUIRES).each(&:invoke).map(&:to_s)
      end

      def report_to(file = nil)
        File.expand_path(File.join(*["reports/cobertura", file.to_s].compact))
      end

      def data_file()
        File.expand_path("reports/cobertura.ser")
      end

    end

    namespace "cobertura" do

      task "instrument" do
        Buildr.projects.each do |project|
          unless project.compile.sources.empty?
            # Instrumented bytecode goes in a different directory. This task creates before running the test
            # cases and monitors for changes in the generate bytecode.
            instrumented = project.file(project.path_to(:target, :instrumented, :classes)=>project.compile.target) do |task|
              Buildr.ant "cobertura" do |ant|
                ant.taskdef :classpath=>requires.join(File::PATH_SEPARATOR), :resource=>"tasks.properties"
                ant.send "cobertura-instrument", :todir=>task.to_s, :datafile=>data_file do
                  ant.fileset(:dir=>project.compile.target.to_s) { ant.include :name=>"**/*.class" }
                end
              end
              touch task.to_s, :verbose=>false
            end
            # We now have two target directories with bytecode. It would make sense to remove compile.target
            # and add instrumented instead, but apparently Cobertura only creates some of the classes, so
            # we need both directories and instrumented must come first.
            project.test.dependencies.unshift instrumented
            project.test.with requires
            project.test.options[:properties]["net.sourceforge.cobertura.datafile"] = data_file
            project.clean { rm_rf instrumented.to_s, :verbose=>false }
          end
        end
      end

      desc "Run the test cases and produce code coverage reports in #{report_to(:html)}"
      task "html"=>["instrument", "test"] do
        puts "Creating test coverage reports in #{report_to(:html)}"
        Buildr.ant "cobertura" do |ant|
          ant.taskdef :classpath=>requires.join(File::PATH_SEPARATOR), :resource=>"tasks.properties"
          ant.send "cobertura-report", :destdir=>report_to(:html), :format=>"html", :datafile=>data_file do
            Buildr.projects.map(&:compile).map(&:sources).flatten.each do |src|
              ant.fileset(:dir=>src.to_s) { ant.include :name=>"**/*.java" } if File.exist?(src.to_s)
            end
          end
        end
      end

      desc "Run the test cases and produce code coverage reports in #{report_to(:xml)}"
      task "xml"=>["instrument", "test"] do
        puts "Creating test coverage reports in #{report_to(:xml)}"
        Buildr.ant "cobertura" do |ant|
          ant.taskdef :classpath=>requires.join(File::PATH_SEPARATOR), :resource=>"tasks.properties"
          ant.send "cobertura-report", :destdir=>report_to(:xml), :format=>"xml", :datafile=>data_file do
            Buildr.projects.map(&:compile).map(&:sources).flatten.each do |src|
              ant.fileset :dir=>src.to_s if File.exist?(src.to_s)
            end
          end
        end
      end

      task "clean" do
        rm_rf [report_to, data_file], :verbose=>false
      end
    end

    task "clean" do
      task("cobertura:clean").invoke if Dir.pwd == Rake.application.original_dir
    end

  end
end
