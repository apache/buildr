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


require 'yaml'


module Buildr

  # Collection of options for controlling Buildr.
  class Options

    # We use this to present environment variable as arrays.
    class EnvArray < Array #:nodoc:
    
      def initialize(name)
        @name = name.upcase
        replace((ENV[@name] || ENV[@name.downcase] || '').split(/\s*,\s*/).reject(&:empty?))
      end

      (Array.instance_methods - Object.instance_methods - Enumerable.instance_methods).sort.each do |method|
        class_eval %{def #{method}(*args, &block) ; result = super ; write ; result ; end}
      end

    private

      def write
        ENV[@name.downcase] = nil
        ENV[@name] = map(&:to_s).join(',')
      end

    end


    # Wraps around the proxy environment variables:
    # * :http -- HTTP_PROXY
    # * :exclude -- NO_PROXY
    class Proxies

      # Returns the HTTP_PROXY URL.
      def http
        ENV['HTTP_PROXY'] || ENV['http_proxy']
      end

      # Sets the HTTP_PROXY URL.
      def http=(url)
        ENV['http_proxy'] = nil
        ENV['HTTP_PROXY'] = url
      end
   
      # Returns list of hosts to exclude from proxying (NO_PROXY). 
      def exclude
        @exclude ||= EnvArray.new('NO_PROXY')
      end

      # Sets list of hosts to exclude from proxy (NO_PROXY). Accepts host name, array of names,
      # or nil to clear the list.
      def exclude=(url)
        exclude.clear
        exclude.concat [url].flatten if url
        exclude
      end

    end

    # :call-seq:
    #   proxy => options
    #
    # Returns the proxy options. Currently supported options are:
    # * :http -- HTTP proxy for use when downloading.
    # * :exclude -- Do not use proxy for these hosts/domains.
    #
    # For example:
    #   options.proxy.http = 'http://proxy.acme.com:8080'
    # You can also set it using the environment variable HTTP_PROXY.
    #
    # You can exclude individual hosts from being proxied, or entire domains, for example:
    #   options.proxy.exclude = 'optimus'
    #   options.proxy.exclude = ['optimus', 'prime']
    #   options.proxy.exclude << '*.internal'
    def proxy
      @proxy ||= Proxies.new
    end

  end


  class << self

    # :call-seq:
    #   options => Options
    #
    # Returns the Buildr options. See Options.
    def options
      @options ||= Options.new
    end

  end

  # :call-seq:
  #   options => Options
  #
  # Returns the Buildr options. See Options.
  def options
    Buildr.options
  end

  # :call-seq:
  #   environment => string or nil
  #
  # Returns the environment name.  Use this when your build depends on the environment,
  # for example, development, production, etc.  The value comes from the BUILDR_ENV
  # environment variable, and defaults to 'development'.
  # 
  # For example:
  #   buildr -e production
  def environment
    ENV['BUILDR_ENV'] ||= 'development'
  end

  # :call-seq:
  #   environment(env)
  #
  # Sets the environment name.
  def environment=(env)
    ENV['BUILDR_ENV'] = env
  end

  # :call-seq:
  #    profile => hash
  #
  # Returns the profile for the current environment.
  def profile
    profiles[environment] ||= {}
  end

  # :call-seq:
  #    profiles => hash
  #
  # Returns all the profiles loaded from the profiles.yaml file.
  def profiles
    unless @profiles
      filename = ['Profiles.yaml', 'profiles.yaml'].map { |fn| File.expand_path(fn, File.dirname(Rake.application.rakefile)) }.
        detect { |filename| File.exist?(filename) }
      @profiles = filename ? YAML::load(File.read(filename)) : {}
    end
    @profiles
  end

end
