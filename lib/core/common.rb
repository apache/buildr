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


require 'tempfile'
require 'pathname'
require 'core/transports'
require 'open-uri'
require 'uri/open-sftp'
require 'rbconfig'


module Kernel #:nodoc:
  # Borrowed from Ruby 1.9.
  def tap
    yield self if block_given?
    self
  end unless method_defined?('tap')
end


class Symbol #:nodoc:
  # Borrowed from Ruby 1.9.
  def to_proc
    Proc.new{|*args| args.shift.__send__(self, *args)}
  end unless method_defined?('to_proc')
end


class File
  class << self

    # Just like File.expand_path, but for windows systems it
    # capitalizes the drive name and ensures backslashes are used
    def normalize_path(path, *dirs)
      path = File.expand_path(path, *dirs)
      if Config::CONFIG["host_os"] =~ /mswin|windows|cygwin/i
        path.gsub!('/', '\\').gsub!(/^[a-zA-Z]+:/) { |s| s.upcase }
      else
        path
      end
    end

    # Return the timestamp of file, without having to create a file task
    def timestamp(file)
      if File.exist?(file)
        File.mtime(file)
      else
        Rake::EARLY
      end
    end
  end
end


class Hash

  class << self

    # :call-seq:
    #   Hash.from_java_properties(string)
    #
    # Returns a hash from a string in the Java properties file format. For example:
    #   str = 'foo=bar\nbaz=fab'
    #   Hash.from_properties(str)
    #   => { 'foo'=>'bar', 'baz'=>'fab' }.to_properties
    def from_java_properties(string)
      string.gsub(/\\\n/, '').split("\n").select { |line| line =~ /^[^#].*=.*/ }.
        map { |line| line.gsub(/\\[trnf\\]/) { |escaped| {?t=>"\t", ?r=>"\r", ?n=>"\n", ?f=>"\f", ?\\=>"\\"}[escaped[1]] } }.
        map { |line| line.split('=') }.
        inject({}) { |hash, (name, value)| hash.merge(name=>value) }
    end

  end

  # :call-seq:
  #   only(keys*) => hash
  #
  # Returns a new hash with only the specified keys.
  #
  # For example:
  #   { :a=>1, :b=>2, :c=>3, :d=>4 }.only(:a, :c)
  #   => { :a=>1, :c=>3 }
  def only(*keys)
    keys.inject({}) { |hash, key| has_key?(key) ? hash.merge(key=>self[key]) : hash }
  end


  # :call-seq:
  #   except(keys*) => hash
  #
  # Returns a new hash without the specified keys.
  #
  # For example:
  #   { :a=>1, :b=>2, :c=>3, :d=>4 }.except(:a, :c)
  #   => { :b=>2, :d=>4 }
  def except(*keys)
    (self.keys - keys).inject({}) { |hash, key| hash.merge(key=>self[key]) }
  end

  # :call-seq:
  #   to_java_properties => string
  #
  # Convert hash to string format used for Java properties file. For example:
  #   { 'foo'=>'bar', 'baz'=>'fab' }.to_properties
  #   => foo=bar
  #      baz=fab
  def to_java_properties
    keys.sort.map { |key|
      value = self[key].gsub(/[\t\r\n\f\\]/) { |escape| "\\" + {"\t"=>"t", "\r"=>"r", "\n"=>"n", "\f"=>"f", "\\"=>"\\"}[escape] }
      "#{key}=#{value}"
    }.join("\n")
  end

end


module Rake #:nodoc
  class FileList
    class << self
      def recursive(*dirs)
        FileList[dirs.map { |dir| File.join(dir, '/**/{*,.*}') }].reject { |file| File.basename(file) =~ /^[.]{1,2}$/ }
      end
    end
  end

  class Task #:nodoc:
    def invoke(*args)
      task_args = TaskArguments.new(arg_names, args)
      invoke_with_call_chain(task_args, Thread.current[:rake_chain] || InvocationChain::EMPTY)
    end

    def invoke_with_call_chain(task_args, invocation_chain)
      new_chain = InvocationChain.append(self, invocation_chain)
      @lock.synchronize do
        if application.options.trace
          puts "** Invoke #{name} #{format_trace_flags}"
        end
        return if @already_invoked
        @already_invoked = true
        invoke_prerequisites(task_args, new_chain)
        begin
          old_chain, Thread.current[:rake_chain] = Thread.current[:rake_chain], new_chain
          execute(task_args) if needed?
        ensure
          Thread.current[:rake_chain] = nil
        end
      end
    end
  end
end


# Also borrowed from Ruby 1.9.
class BasicObject #:nodoc:
  (instance_methods - ['__send__', '__id__', '==', 'send', 'send!', 'respond_to?', 'equal?', 'object_id']).
    each do |method|
      undef_method method
    end

  def self.ancestors
    [Kernel]
  end
end


class OpenObject < Hash

  def initialize(source=nil, &block)
    @hash = Hash.new(&block)
    @hash.update(source) if source
  end

  def [](key)
    @hash[key]
  end

  def []=(key, value)
    @hash[key] = value
  end

  def delete(key)
    @hash.delete(key)
  end

  def to_hash
    @hash.clone
  end

  def method_missing(symbol, *args)
    if symbol.to_s =~ /=$/
      self[symbol.to_s[0..-2].to_sym] = args.first
    else
      self[symbol]
    end
  end
end


module Buildr

  # :call-seq:
  #   struct(hash) => Struct
  #
  # Convenience method for creating an anonymous Struct.
  #
  # For example:
  #   COMMONS             = struct(
  #     :collections      =>'commons-collections:commons-collections:jar:3.1',
  #     :lang             =>'commons-lang:commons-lang:jar:2.1',
  #     :logging          =>'commons-logging:commons-logging:jar:1.0.3',
  #   )
  #
  #   compile.with COMMONS.logging
  def struct(hash)
    Struct.new(nil, *hash.keys).new(*hash.values)  
  end

  # :call-seq:
  #   write(name, content)
  #   write(name) { ... }
  #
  # Write the contents into a file. The second form calls the block and writes the result.
  #
  # For example:
  #   write 'TIMESTAMP', Time.now
  #   write('TIMESTAMP') { Time.now }
  #
  # Yields to the block before writing the file, so you can chain read and write together.
  # For example:
  #   write('README') { read('README').sub("${build}", Time.now) }
  def write(name, content = nil)
    mkpath File.dirname(name), :verbose=>false
    content = yield if block_given?
    File.open(name.to_s, 'wb') { |file| file.write content.to_s }
    content.to_s
  end

  # :call-seq:
  #   read(name) => string
  #   read(name) { |string| ... } => result
  #
  # Reads and returns the contents of a file. The second form yields to the block and returns
  # the result of the block.
  #
  # For example:
  #   puts read('README')
  #   read('README') { |text| puts text }
  def read(name)
    contents = File.open(name.to_s) { |f| f.read }
    if block_given?
      yield contents
    else
      contents
    end
  end

  # :call-seq:
  #    download(url_or_uri) => task
  #    download(path=>url_or_uri) =>task
  #
  # Create a task that will download a file from a URL.
  #
  # Takes a single argument, a hash with one pair. The key is the file being
  # created, the value if the URL to download. The task executes only if the
  # file does not exist; the URL is not checked for updates.
  #
  # The task will show download progress on the console; if there are MD5/SHA1
  # checksums on the server it will verify the download before saving it.
  #
  # For example:
  #   download 'image.jpg'=>'http://example.com/theme/image.jpg'
  def download(args)
    args = URI.parse(args) if String === args
    if URI === args
      # Given only a download URL, download into a temporary file.
      # You can infer the file from task name.
      temp = Tempfile.open(File.basename(args.to_s))
      file(temp.path).tap do |task|
        # Since temporary file exists, force a download.
        class << task ; def needed? ; true ; end ; end
        task.sources << args
        task.enhance { args.download temp }
      end
    else
      # Download to a file created by the task.
      fail unless args.keys.size == 1
      uri = URI.parse(args.values.first.to_s)
      file(args.keys.first).tap do |task|
        task.sources << uri
        task.enhance { uri.download task.name }
      end
    end

  end

end


# Add a touch of colors (red) to warnings.
HighLine.use_color = PLATFORM !~ /win32/
module Kernel #:nodoc:

  alias :warn_without_color :warn
  def warn(message)
    warn_without_color $terminal.color(message.to_s, :red)
  end

  # :call-seq:
  #   warn_deprecated(message)
  #
  # Use with deprecated methods and classes. This method automatically adds the file name and line number,
  # and the text 'Deprecated' before the message, and eliminated duplicate warnings. It only warns when
  # running in verbose mode.
  #
  # For example:
  #   warn_deprecated 'Please use new_foo instead of foo.'
  def warn_deprecated(message) #:nodoc:
    return unless verbose
    "#{caller[1]}: Deprecated: #{message}".tap do |message|
      @deprecated ||= {}
      unless @deprecated[message]
        @deprecated[message] = true
        warn message
      end
    end
  end

end
