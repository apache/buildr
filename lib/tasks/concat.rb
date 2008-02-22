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

  # A file task that concatenates all its prerequisites to create a new file.
  #
  # For example:
  #   concat("master.sql"=>["users.sql", "orders.sql", reports.sql"]
  #
  # See also Buildr#concat.
  class ConcatTask < Rake::FileTask
    def initialize(*args) #:nodoc:
      super
      enhance do |task|
        content = prerequisites.inject("") do |content, prereq|
          content << File.read(prereq.to_s) if File.exists?(prereq) && !File.directory?(prereq)
          content
        end
        File.open(task.name, "wb") { |file| file.write content }
      end
    end
  end

  # :call-seq:
  #    concat(target=>files) => task
  #
  # Creates and returns a file task that concatenates all its prerequisites to create
  # a new file. See #ConcatTask.
  #
  # For example:
  #   concat("master.sql"=>["users.sql", "orders.sql", reports.sql"]
  def concat(args)
    file, arg_names, deps = Rake.application.resolve_args([args])
    ConcatTask.define_task(File.expand_path(file)=>deps)
  end

end
