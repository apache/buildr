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

module Java #:nodoc:

  class << self

    # *Deprecated*: Use Java::Commands.java instead.
    def java(*args, &block)
      return send(:method_missing, :java) if args.empty?
      Buildr.application.deprecated 'Use Java::Commands.java instead.'
      Commands.java(*args, &block)
    end

    # *Deprecated*: Use Java::Commands.apt instead.
    def apt(*args)
      Buildr.application.deprecated 'Use Java::Commands.apt instead.'
      Commands.apt(*args)
    end

    # *Deprecated*: Use Java::Commands.javac instead.
    def javac(*args)
      Buildr.application.deprecated 'Use Java::Commands.javac instead.'
      Commands.javac(*args)
    end

    # *Deprecated*: Use Java::Commands.javadoc instead.
    def javadoc(*args)
      Buildr.application.deprecated 'Use Java::Commands.javadoc instead.'
      Commands.javadoc(*args)
    end

    # *Deprecated:* Use ENV_JAVA['java.version'] instead.
    def version
      Buildr.application.deprecated 'Use ENV_JAVA[\'java.version\'] instead.'
      Java.load
      ENV_JAVA['java.version']
    end

    # *Deprecated:* Use ENV['JAVA_HOME'] instead
    def home
      Buildr.application.deprecated 'Use ENV[\'JAVA_HOME\'] instead.'
      ENV['JAVA_HOME']
    end

  end


  class Options

    # *Deprecated:* Use ENV['JAVA_OPTS'] instead.
    def java_args
      Buildr.application.deprecated "Use ENV['JAVA_OPTS'] instead"
      (ENV["JAVA_OPTS"] || ENV["JAVA_OPTIONS"]).to_s.split
    end

    # *Deprecated:* Use ENV['JAVA_OPTS'] instead.
    def java_args=(args)
      Buildr.application.deprecated "Use ENV['JAVA_OPTS'] instead"
      ENV['JAVA_OPTS'] = Array(args).join(' ')
    end

  end

end
