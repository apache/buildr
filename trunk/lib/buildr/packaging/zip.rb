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


require 'zip/zip'
require 'zip/zipfilesystem'


module Buildr

  # Base class for ZipTask, TarTask and other archives.
  class ArchiveTask < Rake::FileTask

    # Which files go where. All the rules for including, excluding and merging files
    # are handled by this object.
    class Path #:nodoc:

      # Returns the archive from this path.
      attr_reader :root
      
      def initialize(root, path)
        @root = root
        @path = path.empty? ? path : "#{path}/"
        @includes = FileList[]
        @excludes = []
        # Expand source files added to this path.
        expand_src = proc { @includes.map{ |file| file.to_s }.uniq }
        @sources = [ expand_src ]
        # Add files and directories added to this path.
        @actions = [] << proc do |file_map|
          expand_src.call.each do |path|
            unless excluded?(path)
              if File.directory?(path)
                in_directory path do |file, rel_path|
                  dest = "#{@path}#{rel_path}"
                  puts "Adding #{dest}" if Buildr.application.options.trace
                  file_map[dest] = file
                end
              else
                puts "Adding #{@path}#{File.basename(path)}" if Buildr.application.options.trace
                file_map["#{@path}#{File.basename(path)}"] = path
              end
            end
          end
        end
      end

      # :call-seq:
      #   include(*files) => self
      #   include(*files, :path=>path) => self
      #   include(file, :as=>name) => self
      #   include(:from=>path) => self
      #   include(*files, :merge=>true) => self
      def include(*args)
        options = args.pop if Hash === args.last
        files = args.flatten

        if options.nil? || options.empty?
          @includes.include *files.flatten
        elsif options[:path]
          sans_path = options.reject { |k,v| k == :path }
          path(options[:path]).include *files + [sans_path]
        elsif options[:as]
          raise 'You can only use the :as option in combination with the :path option' unless options.size == 1
          raise 'You can only use one file with the :as option' unless files.size == 1
          include_as files.first.to_s, options[:as]
        elsif options[:from]
          raise 'You can only use the :from option in combination with the :path option' unless options.size == 1
          raise 'You canont use the :from option with file names' unless files.empty?
          [options[:from]].flatten.each { |path| include_as path.to_s, '.' }
        elsif options[:merge]
          raise 'You can only use the :merge option in combination with the :path option' unless options.size == 1
          files.each { |file| merge file }
        else
          raise "Unrecognized option #{options.keys.join(', ')}"
        end
        self
      end
      alias :add :include
      alias :<< :include

      # :call-seq:
      #   exclude(*files) => self
      def exclude(*files)
        files = files.flatten.map(&:to_s) 
        @excludes |= files
        @excludes |= files.reject { |f| f =~ /\*$/ }.map { |f| "#{f}/*" }
        self
      end

      # :call-seq:
      #   merge(*files) => Merge
      #   merge(*files, :path=>name) => Merge
      def merge(*args)
        options = Hash === args.last ? args.pop : {}
        files = args.flatten
        rake_check_options options, :path
        raise ArgumentError, "Expected at least one file to merge" if files.empty?
        path = options[:path] || @path
        expanders = files.collect do |file|
          @sources << proc { file.to_s }
          expander = ZipExpander.new(file)
          @actions << proc { |file_map| expander.expand(file_map, path) }
          expander
        end
        Merge.new(expanders)
      end

      # Returns a Path relative to this one.
      def path(path)
        return self if path.nil?
        return root.path(path[1..-1]) if path[0] == ?/
        root.path("#{@path}#{path}")
      end

      # Returns all the source files.
      def sources() #:nodoc:
        @sources.map{ |source| source.call }.flatten
      end

      def add_files(file_map) #:nodoc:
        @actions.each { |action| action.call(file_map) }
      end

      def to_s()
        @path
      end

    protected

      def include_as(source, as)
        @sources << proc { source }
        @actions << proc do |file_map|
          file = source.to_s
          unless excluded?(file)
            if File.directory?(file)
              in_directory file do |file, rel_path|
                path = rel_path.split('/')[1..-1]
                path.unshift as unless as == '.'
                dest = "#{@path}#{path.join('/')}"
                puts "Adding #{dest}" if Buildr.application.options.trace
                file_map[dest] = file
              end
            else
              puts "Adding #{@path}#{as}" if Buildr.application.options.trace
              file_map["#{@path}#{as}"] = file
            end
          end
        end
      end

      def in_directory(dir)
        prefix = Regexp.new('^' + Regexp.escape(File.dirname(dir) + File::SEPARATOR))
        Util.recursive_with_dot_files(dir).reject { |file| excluded?(file) }.
          each { |file| yield file, file.sub(prefix, '') }
      end

      def excluded?(file)
        @excludes.any? { |exclude| File.fnmatch(exclude, file, File::FNM_PATHNAME) }
      end

    end

    class Merge
      def initialize(expanders)
        @expanders = expanders
      end

      def include(*files)
        @expanders.each { |expander| expander.include(*files) }
        self
      end
      alias :<< :include

      def exclude(*files)
        @expanders.each { |expander| expander.exclude(*files) }
        self
      end
    end


    # Extend one Zip file into another.
    class ZipExpander #:nodoc:

      def initialize(zip_file)
        @zip_file = zip_file.to_s
        @includes = []
        @excludes = []
      end

      def include(*files)
        @includes |= files
        self
      end
      alias :<< :include

      def exclude(*files)
        @excludes |= files
        self
      end

      def expand(file_map, path)
        @includes = ['**/*'] if @includes.empty?
        Zip::ZipFile.open(@zip_file) do |source|
          source.entries.reject { |entry| entry.directory? }.each do |entry|
            if @includes.any? { |pattern| File.fnmatch(pattern, entry.name, File::FNM_PATHNAME) } &&
               !@excludes.any? { |pattern| File.fnmatch(pattern, entry.name, File::FNM_PATHNAME) }
              dest = path =~ /^\/?$/ ? entry.name : Util.relative_path(path + "/" + entry.name)
              puts "Adding #{dest}" if Buildr.application.options.trace
              file_map[dest] = lambda { |output| output.write source.read(entry) }
            end
          end
        end
      end

    end


    def initialize(*args) #:nodoc:
      super
      clean

      # Make sure we're the last enhancements, so other enhancements can add content.
      enhance do
        @file_map = {}
        enhance do
          send 'create' if respond_to?(:create)
          # We're here because the archive file does not exist, or one of the files is newer than the archive contents;
          # we need to make sure the archive doesn't exist (e.g. opening an existing Zip will add instead of create).
          # We also want to protect against partial updates.
          rm name, :verbose=>false rescue nil
          mkpath File.dirname(name), :verbose=>false
          begin
            @paths.each do |name, object|
              @file_map[name] = nil unless name.empty?
              object.add_files(@file_map)
            end
            create_from @file_map
          rescue
            rm name, :verbose=>false rescue nil
            raise
          end
        end
      end
    end

    # :call-seq:
    #   clean => self
    # 
    # Removes all previously added content from this archive. 
    # Use this method if you want to remove default content from a package.
    # For example, package(:jar) by default includes compiled classes and resources,
    # using this method, you can create an empty jar and afterwards add the
    # desired content to it.
    # 
    #    package(:jar).clean.include path_to('desired/content')
    def clean
      @paths = { '' => Path.new(self, '') }
      @prepares = []
      self
    end

    # :call-seq:
    #   include(*files) => self
    #   include(*files, :path=>path) => self
    #   include(file, :as=>name) => self
    #   include(:from=>path) => self
    #   include(*files, :merge=>true) => self
    #
    # Include files in this archive, or when called on a path, within that path. Returns self.
    #
    # The first form accepts a list of files, directories and glob patterns and adds them to the archive.
    # For example, to include the file foo, directory bar (including all files in there) and all files under baz:
    #   zip(..).include('foo', 'bar', 'baz/*')
    #
    # The second form is similar but adds files/directories under the specified path. For example,
    # to add foo as bar/foo:
    #   zip(..).include('foo', :path=>'bar')
    # The :path option is the same as using the path method:
    #   zip(..).path('bar').include('foo')
    # All other options can be used in combination with the :path option.
    #
    # The third form adds a file or directory under a different name. For example, to add the file foo under the
    # name bar:
    #   zip(..).include('foo', :as=>'bar')
    #
    # The fourth form adds the contents of a directory using the directory as a prerequisite:
    #   zip(..).include(:from=>'foo')
    # Unlike <code>include('foo')</code> it includes the contents of the directory, not the directory itself.
    # Unlike <code>include('foo/*')</code>, it uses the directory timestamp for dependency management.
    #
    # The fifth form includes the contents of another archive by expanding it into this archive. For example:
    #   zip(..).include('foo.zip', :merge=>true).include('bar.zip')
    # You can also use the method #merge.
    def include(*files)
      @paths[''].include *files
      self
    end 
    alias :add :include
    alias :<< :include
   
    # :call-seq:
    #   exclude(*files) => self
    # 
    # Excludes files and returns self. Can be used in combination with include to prevent some files from being included.
    def exclude(*files)
      @paths[''].exclude *files
      self
    end 

    # :call-seq:
    #   merge(*files) => Merge
    #   merge(*files, :path=>name) => Merge
    #
    # Merges another archive into this one by including the individual files from the merged archive.
    #
    # Returns an object that supports two methods: include and exclude. You can use these methods to merge
    # only specific files. For example:
    #   zip(..).merge('src.zip').include('module1/*')
    def merge(*files)
      @paths[''].merge *files
    end 

    # :call-seq:
    #   path(name) => Path
    #
    # Returns a path object. Use the path object to include files under a path, for example, to include
    # the file 'foo' as 'bar/foo':
    #   zip(..).path('bar').include('foo')
    #
    # Returns a Path object. The Path object implements all the same methods, like include, exclude, merge
    # and so forth. It also implements path and root, so that:
    #   path('foo').path('bar') == path('foo/bar')
    #   path('foo').root == root
    def path(name)
      return @paths[''] if name.nil?
      normalized = name.split('/').inject([]) do |path, part|
        case part
        when '.', nil, ''
          path
        when '..'
          path[0...-1]
        else
          path << part
        end
      end.join('/')
      @paths[normalized] ||= Path.new(self, normalized)
    end

    # :call-seq:
    #   root() => ArchiveTask
    #
    # Call this on an archive to return itself, and on a path to return the archive.
    def root()
      self
    end

    # :call-seq:
    #   with(options) => self
    #
    # Passes options to the task and returns self. Some tasks support additional options, for example,
    # the WarTask supports options like :manifest, :libs and :classes.
    #
    # For example:
    #   package(:jar).with(:manifest=>'MANIFEST_MF')
    def with(options)
      options.each do |key, value|
        begin
          send "#{key}=", value
        rescue NoMethodError
          raise ArgumentError, "#{self.class.name} does not support the option #{key}"
        end
      end
      self
    end

    def invoke_prerequisites(args, chain) #:nodoc:
      @prepares.each { |prepare| prepare.call(self) }
      @prepares.clear
      @prerequisites |= @paths.collect { |name, path| path.sources }.flatten
      super
    end
    
    def needed?() #:nodoc:
      return true unless File.exist?(name)
      # You can do something like:
      #   include('foo', :path=>'foo').exclude('foo/bar', path=>'foo').
      #     include('foo/bar', :path=>'foo/bar')
      # This will play havoc if we handled all the prerequisites together
      # under the task, so instead we handle them individually for each path.
      #
      # We need to check that any file we include is not newer than the
      # contents of the Zip. The file itself but also the directory it's
      # coming from, since some tasks touch the directory, e.g. when the
      # content of target/classes is included into a WAR.
      most_recent = @paths.collect { |name, path| path.sources }.flatten.
        each { |src| File.directory?(src) ? Util.recursive_with_dot_files(src) | [src] : src }.flatten.
        select { |file| File.exist?(file) }.collect { |file| File.stat(file).mtime }.max
      File.stat(name).mtime < (most_recent || Rake::EARLY) || super
    end

  protected

    # Adds a prepare block. These blocks are called early on for adding more content to
    # the archive, before invoking prerequsities. Anything you add here will be invoked
    # as a prerequisite and used to determine whether or not to generate this archive.
    # In contrast, enhance blocks are evaluated after it was decided to create this archive.
    def prepare(&block)
      @prepares << block
    end

    def []=(key, value) #:nodoc:
      raise ArgumentError, "This task does not support the option #{key}."
    end

  end

  # The ZipTask creates a new Zip file. You can include any number of files and and directories,
  # use exclusion patterns, and include files into specific directories.
  #
  # For example:
  #   zip('test.zip').tap do |task|
  #     task.include 'srcs'
  #     task.include 'README', 'LICENSE'
  #   end
  #
  # See Buildr#zip and ArchiveTask.
  class ZipTask < ArchiveTask

    # Compression leve for this Zip.
    attr_accessor :compression_level

    def initialize(*args) #:nodoc:
      self.compression_level = Zlib::NO_COMPRESSION
      super
    end

  private

    def create_from(file_map)
      Zip::ZipOutputStream.open name do |zip|
        seen = {}
        mkpath = lambda do |dir|
          unless dir == '.' || seen[dir]
            mkpath.call File.dirname(dir)
            zip.put_next_entry(dir + '/', compression_level)
            seen[dir] = true
          end
        end

        file_map.each do |path, content|
          mkpath.call File.dirname(path)
          if content.respond_to?(:call)
            zip.put_next_entry(path, compression_level)
            content.call zip
          elsif content.nil? || File.directory?(content.to_s)
            mkpath.call path
          else
            zip.put_next_entry(path, compression_level)
            File.open content.to_s, 'rb' do |is|
              while data = is.read(4096)
                zip << data
              end
            end
          end
        end
      end
    end

  end


  # :call-seq:
  #    zip(file) => ZipTask
  #
  # The ZipTask creates a new Zip file. You can include any number of files and
  # and directories, use exclusion patterns, and include files into specific
  # directories.
  #
  # For example:
  #   zip('test.zip').tap do |task|
  #     task.include 'srcs'
  #     task.include 'README', 'LICENSE'
  #   end
  def zip(file)
    ZipTask.define_task(file)
  end


  # An object for unzipping a file into a target directory. You can tell it to include
  # or exclude only specific files and directories, and also to map files from particular
  # paths inside the zip file into the target directory. Once ready, call #extract.
  #
  # Usually it is more convenient to create a file task for extracting the zip file
  # (see #unzip) and pass this object as a prerequisite to other tasks.
  #
  # See Buildr#unzip.
  class Unzip

    # The zip file to extract.
    attr_accessor :zip_file
    # The target directory to extract to.
    attr_accessor :target

    # Initialize with hash argument of the form target=>zip_file.
    def initialize(args)
      @target, arg_names, @zip_file = Buildr.application.resolve_args([args])
      @paths = {}
    end

    # :call-seq:
    #   extract()
    #
    # Extract the zip file into the target directory.
    #
    # You can call this method directly. However, if you are using the #unzip method,
    # it creates a file task for the target directory: use that task instead as a
    # prerequisite. For example:
    #   build unzip(dir=>zip_file)
    # Or:
    #   unzip(dir=>zip_file).target.invoke
    def extract()
      # If no paths specified, then no include/exclude patterns
      # specified. Nothing will happen unless we include all files.
      if @paths.empty?
        @paths[nil] = FromPath.new(self, nil)
      end

      # Otherwise, empty unzip creates target as a file when touching.
      mkpath target.to_s, :verbose=>false
      Zip::ZipFile.open(zip_file.to_s) do |zip|
        entries = zip.collect
        @paths.each do |path, patterns|
          patterns.map(entries).each do |dest, entry|
            next if entry.directory?
            dest = File.expand_path(dest, target.to_s)
            puts "Extracting #{dest}" if Buildr.application.options.trace
            mkpath File.dirname(dest), :verbose=>false rescue nil
            entry.extract(dest) { true }
          end
        end
      end
      # Let other tasks know we updated the target directory.
      touch target.to_s, :verbose=>false
    end

    # :call-seq:
    #   include(*files) => self
    #   include(*files, :path=>name) => self
    #
    # Include all files that match the patterns and returns self.
    #
    # Use include if you only want to unzip some of the files, by specifying
    # them instead of using exclusion. You can use #include in combination
    # with #exclude.
    def include(*files)
      if Hash === files.last
        from_path(files.pop[:path]).include *files
      else
        from_path(nil).include *files
      end
      self
    end
    alias :add :include

    # :call-seq:
    #   exclude(*files) => self
    #
    # Exclude all files that match the patterns and return self.
    #
    # Use exclude to unzip all files except those that match the pattern.
    # You can use #exclude in combination with #include.
    def exclude(*files)
      if Hash === files.last
        from_path(files.pop[:path]).exclude *files
      else
        from_path(nil).exclude *files
      end
      self
    end

    # :call-seq:
    #   from_path(name) => Path
    #
    # Allows you to unzip from a path. Returns an object you can use to
    # specify which files to include/exclude relative to that path.
    # Expands the file relative to that path.
    #
    # For example:
    #   unzip(Dir.pwd=>'test.jar').from_path('etc').include('LICENSE')
    # will unzip etc/LICENSE into ./LICENSE.
    #
    # This is different from:
    #  unzip(Dir.pwd=>'test.jar').include('etc/LICENSE')
    # which unzips etc/LICENSE into ./etc/LICENSE.
    def from_path(name)
      @paths[name] ||= FromPath.new(self, name)
    end
    alias :path :from_path

    # :call-seq:
    #   root() => Unzip
    #
    # Returns the root path, essentially the Unzip object itself. In case you are wondering
    # down paths and want to go back.
    def root()
      self
    end

    # Returns the path to the target directory.
    def to_s()
      target.to_s
    end

    class FromPath #:nodoc:

      def initialize(unzip, path)
        @unzip = unzip
        if path
          @path = path[-1] == ?/ ? path : path + '/'
        else
          @path = ''
        end
      end

      # See UnzipTask#include
      def include(*files) #:doc:
        @include ||= []
        @include |= files
        self
      end

      # See UnzipTask#exclude
      def exclude(*files) #:doc:
        @exclude ||= []
        @exclude |= files
        self
      end

      def map(entries)
        includes = @include || ['**/*']
        excludes = @exclude || []
        entries.inject({}) do |map, entry|
          short = entry.name.sub(@path, '')
          if includes.any? { |pat| File.fnmatch(pat, short, File::FNM_PATHNAME) } &&
             !excludes.any? { |pat| File.fnmatch(pat, short, File::FNM_PATHNAME) }
            map[short] = entry
          end
          map
        end
      end

      # Documented in Unzip.
      def root()
        @unzip
      end

      # The target directory to extract to.
      def target()
        @unzip.target
      end

    end

  end

  # :call-seq:
  #    unzip(to_dir=>zip_file) => Zip
  #
  # Creates a task that will unzip a file into the target directory. The task name
  # is the target directory, the prerequisite is the file to unzip.
  #
  # This method creates a file task to expand the zip file. It returns an Unzip object
  # that specifies how the file will be extracted. You can include or exclude specific
  # files from within the zip, and map to different paths.
  #
  # The Unzip object's to_s method return the path to the target directory, so you can
  # use it as a prerequisite. By keeping the Unzip object separate from the file task,
  # you overlay additional work on top of the file task.
  #
  # For example:
  #   unzip('all'=>'test.zip')
  #   unzip('src'=>'test.zip').include('README', 'LICENSE') 
  #   unzip('libs'=>'test.zip').from_path('libs')
  def unzip(args)
    target, arg_names, zip_file = Buildr.application.resolve_args([args])
    task = file(File.expand_path(target.to_s)=>zip_file)
    Unzip.new(task=>zip_file).tap do |setup|
      task.enhance { setup.extract }
    end
  end

end


module Zip #:nodoc:

  class ZipCentralDirectory #:nodoc:
    # Patch to add entries in alphabetical order.
    def write_to_stream(io)
      offset = io.tell
      @entrySet.sort { |a,b| a.name <=> b.name }.each { |entry| entry.write_c_dir_entry(io) }
      write_e_o_c_d(io, offset)
    end
  end

end 
