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


require 'tasks/zip'
require 'archive/tar/minitar'

module Buildr

  # The TarTask creates a new Tar file. You can include any number of files and and directories,
  # use exclusion patterns, and include files into specific directories.
  #
  # To create a GZipped Tar, either set the gzip option to true, or use the .tgz or .gz suffix.
  #
  # For example:
  #   tar("test.tgz").tap do |task|
  #     task.include "srcs"
  #     task.include "README", "LICENSE"
  #   end
  #
  # See Buildr#tar and ArchiveTask.
  class TarTask < ArchiveTask

    # To create a GZipped Tar, either set this option to true, or use the .tgz/.gz suffix.
    attr_accessor :gzip
    # Permission mode for files contained in the Tar.  Defaults to 0755.
    attr_accessor :mode

    def initialize(*args, &block) #:nodoc:
      super
      self.gzip = name =~ /\.[t?]gz$/
      self.mode = '0755'
    end

  private

    def create_from(file_map)
      if gzip
        StringIO.new.tap do |io|
          create_tar io, file_map
          io.seek 0
          Zlib::GzipWriter.open(name) { |gzip| gzip.write io.read }
        end
      else
        File.open(name, 'wb') { |file| create_tar file, file_map }
      end
    end

    def create_tar(out, file_map)
      Archive::Tar::Minitar::Writer.open(out) do |tar|
        options = { :mode=>mode || '0755', :mtime=>Time.now }

        file_map.each do |path, content|
          if content.respond_to?(:call)
            tar.add_file(path, options) { |os, opts| content.call os }
          elsif content.nil? || File.directory?(content.to_s)
          else
            File.open content.to_s, 'rb' do |is|
              tar.add_file path, options.merge(:mode=>is.stat.mode, :mtime=>is.stat.mtime, :uid=>is.stat.uid, :gid=>is.stat.gid) do |os, opts|
                while data = is.read(4096)
                  os.write(data)
                end
              end
            end
          end
        end
      end
    end

  end

end


# :call-seq:
#    tar(file) => TarTask
#
# The TarTask creates a new Tar file. You can include any number of files and
# and directories, use exclusion patterns, and include files into specific
# directories.
#
# To create a GZipped Tar, either set the gzip option to true, or use the .tgz or .gz suffix.
#
# For example:
#   tar("test.tgz").tap do |tgz|
#     tgz.include "srcs"
#     tgz.include "README", "LICENSE"
#   end
def tar(file)
  TarTask.define_task(file)
end
