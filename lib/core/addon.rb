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


require 'java/artifact'


module Buildr

  # Addons are a mechanicm for sharing extensions, tasks and common code across builds,
  # using remote and local repositories.
  #
  # An addon is a collection of files, a ZIP archive when distributed and an exploded
  # directory when used locally.  They are installed and expanded into the local repository.
  #
  # Addons provide functionality in three different ways:
  # * The addon directory is added to the $LOAD_PATH, and its files can be accessed from
  #    the build tasks, typically using +require+.
  # * The +init.rb+ file is required by default, if present.  An addon can use this to
  #   install project extensions, introduce new tasks, install libraries, etc.
  # * Task files that go in the +tasks+ sub-directory with the extension +.rake+ are
  #   automatically loaded after the buildfile.  Use these to introduce addition tasks.
  #
  # The addon method supports options that are set on the addon on first use.  The +init.rb+
  # file can access these options through the global variable $ADDON.
  #
  # Addons are referenced by a qualified name.  For local and remote repositories, the
  # last part of the qualified name maps to the artifact identifier, the rest is the group
  # identifier.  For example, 'org.apache.buildr.openjpa:1.0' becomes
  # 'org.apache.buildr:openjpa:zip:1.0'.
  class Addon

    class << self

      # Returns all the loaded addons.
      def list
        @addons.values
      end

      def load(from, options = nil) #:nodoc:
        options ||= {}
        case from
        when Rake::FileTask
          target = from.to_s
          name = target.pathmap('%n')
        when String
          name, version, *rest = from.split(':')
          fail "Expecting <name>:<version>, found #{from}." unless name && version && rest.empty?
          group = name.split('.')
          id = group.pop
          fail "Addon name is qualified, like foo.bar or foo.bar.baz, but not foo." if group.empty?
          artifact = Buildr.artifact("#{group.join('.')}:#{id}:zip:#{version}")
          target = artifact.to_s.ext
          Buildr.unzip(target=>artifact)
        else
          fail "Can only load addon from repository (name:version) or file task."
        end
        if addon = @addons[name]
          fail "Attempt to load addon #{name} with two different version numbers, first (#{addon.version}) and now (#{version})." unless
            addon.version == version
          false
        else
          @addons[name] = new(name, version, target, options)
          true
        end
      end

    end

    @addons = {}

    # Addon name.
    attr_reader :name
    # Version number (may be nil).
    attr_reader :version
    # The path for the addon directory.
    attr_reader :path

    include Enumerable

    def initialize(name, version, path, options) #:nodoc:
      @name, @version, @options = name, version, options
      @path = File.expand_path(path)
      file(@path).invoke
      raise "#{@path} is not a directory." unless File.directory?(@path)
      begin
        $ADDON = self
        $LOAD_PATH << @path unless $LOAD_PATH.include?(@path)
        init_file = File.join(@path, 'init.rb')
        require init_file if File.exist?(init_file)
        import *FileList[File.join(@path, 'tasks/*.rake')]
      rescue
        $LOAD_PATH.delete @path
      ensure
        $ADDON = nil
      end
    end

    # Returns the value of the option.
    def [](name)
      @options[name]
    end

    # Sets the value of the option.
    def []=(name, value)
      @options[name] = value
    end

    def each(&block) #:nodoc:
      @options.each(&block)
    end

    def to_s #:nodoc:
      version ? "#{name}:#{version}" : name
    end

  end

  # :call-seq:
  #   addon(id, options?)
  #   addon(task, options?)
  #
  # Use this to download and install an addon.  The first form takes the addon identifier,
  # a string that contains the qualified name, colon and version number.  For example:
  #   addon 'org.apache.buildr.openjpa:1.0'
  # Some addons accept options passed as a hash argument.
  #
  # The second form takes a file task that points to the directory containing the addon.
  def addon(from, options = nil)
    Addon.load(from, options)
  end

end
