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


require File.join(File.dirname(__FILE__), 'spec_helpers')

describe Buildr::Eclipse do

  describe "eclipse's .project file" do
    
    describe 'scala project' do

      SCALA_NATURE = 'ch.epfl.lamp.sdt.core.scalanature'
      JAVA_NATURE  = 'org.eclipse.jdt.core.javanature'

      SCALA_BUILDER = 'ch.epfl.lamp.sdt.core.scalabuilder'
      JAVA_BUILDER  = 'org.eclipse.jdt.core.javabuilder'
      
      def project_natures
        task('eclipse').invoke
        REXML::Document.new(File.open('.project')).
          root.elements.collect("natures/nature") { |n| n.text }
      end

      def build_commands
        task('eclipse').invoke
        REXML::Document.new(File.open('.project')).
          root.elements.collect("buildSpec/buildCommand/name") { |n| n.text }
      end

      before do
        write 'buildfile'
        write 'src/main/scala/Main.scala'
      end
      
      it 'should have Scala nature before Java nature' do
        define('foo')
        project_natures.should include(SCALA_NATURE)
        project_natures.should include(JAVA_NATURE)
        project_natures.index(SCALA_NATURE).should < project_natures.index(JAVA_NATURE)
      end

      it 'should have Scala build command and no Java build command' do
        define('foo')
        build_commands.should include(SCALA_BUILDER)
        build_commands.should_not include(JAVA_BUILDER)
      end
    end
  end
  
  describe "eclipse's .classpath file" do
    
    describe 'scala project' do

      SCALA_CONTAINER = 'ch.epfl.lamp.sdt.launching.SCALA_CONTAINER'
      JAVA_CONTAINER  = 'org.eclipse.jdt.launching.JRE_CONTAINER'
      
      def classpath_containers attribute='path'
        task('eclipse').invoke
        REXML::Document.new(File.open('.classpath')).
          root.elements.collect("classpathentry[@kind='con']") { |n| n.attributes[attribute] }
      end

      before do
        write 'buildfile'
        write 'src/main/scala/Main.scala'
      end
      
      it 'should have SCALA_CONTAINER before JRE_CONTAINER' do
        define('foo')
        classpath_containers.should include(SCALA_CONTAINER)
        classpath_containers.should include(JAVA_CONTAINER)
        classpath_containers.index(SCALA_CONTAINER).should < classpath_containers.index(JAVA_CONTAINER)
      end
    end
    
    describe 'source folders' do
      
      def classpath_sources attribute='path'
        task('eclipse').invoke
        REXML::Document.new(File.open('.classpath')).
          root.elements.collect("classpathentry[@kind='src']") { |n| n.attributes[attribute] }
      end

      before do
        write 'buildfile'
        write 'src/main/java/Main.java'
        write 'src/test/java/Test.java'
      end
      
      it 'should accept a default main source folder' do
        define('foo')
        classpath_sources.should include('src/main/java')
      end
      
      it 'should accept a user-defined main source folder' do
        define('foo') { compile path_to('src/java') }
        write 'src/java/Foo.java'
        classpath_sources.should include('src/java')
      end
      
      it 'should accept a default test source folder' do
        define('foo')
        classpath_sources.should include('src/test/java')
      end
      
      it 'should accept a user-defined test source folder' do
        define('foo') { test.compile path_to('src/test') }
        classpath_sources.should include('src/test')
      end
      
      it 'should accept a default main resource folder' do
        write 'src/main/resources/config.xml'
        define('foo')
        classpath_sources.should include('src/main/resources')
      end
    
      it 'should accept a default test resource folder' do
        write 'src/test/resources/config-test.xml'
        define('foo')
        classpath_sources.should include('src/test/resources')
      end
    
      it 'should ignore CVS and SVN files' do
        define('foo')
        classpath_sources('excluding').uniq.should == ['**/.svn/|**/CVS/']
      end
      
    end
  end
end
