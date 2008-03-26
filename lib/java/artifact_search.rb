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
  module ArtifactSearch
    extend self
    
    def enabled=(bool); @enabled = true & bool; end
    def enabled?; @enabled; end
    self.enabled = true
    
    def include(method = nil)
      (@includes ||= []).tap { push method if method }
    end

    def exclude(method = nil)
      (@excludes ||= []).tap { push method if method }
    end
    
    def best_version(spec)
      spec = Artifact.to_hash(spec)
      spec[:version] = requirement = VersionRequirement.create(spec[:version])
      select = lambda do |candidates|
        candidates.find { |candidate| requirement.satisfied_by?(candidate) }
      end
      result = nil
      methods = search_methods
      if requirement.has_alternatives?
        until result || methods.empty?
          method = methods.shift
          type = method.keys.first
          from = method[type]
          if (include.empty? || !(include & [:all, type, from]).empty?) &&
              (exclude & [:all, type, from]).empty?
            if from.respond_to?(:call)
              versions = from.call(spec.dup)
            else
              versions = send("#{type}_versions", spec.dup, *from)
            end
            result = select[versions]
          end
        end
      end
      result ||= requirement.default
      raise "Could not find #{Artifact.to_spec(spec)}"  +
        "\n You may need to use an specific version instead of a requirement" +
        "\n More Docu." unless result
      spec.merge :version => result
    end
    
    def requirement?(spec)
      VersionRequirement.requirement?(spec[:version])
    end
    
    private
    def search_methods
      [].tap do
        push :runtime => [Artifact.list]
        push :local => Buildr.repositories.local
        Buildr.repositories.remote.each { |remote| push :remote => remote }
        push :mvnrepository => []
      end
    end

    def depend_version(spec)
      spec[:version][/[\w\.]+/]
    end

    def runtime_versions(spec, artifacts)
      spec_classif = spec.values_at(:group, :id, :type)
      artifacts.inject([]) do |in_memory, str|
        candidate = Artifact.to_hash(str)
        if spec_classif == candidate.values_at(:group, :id, :type)
          in_memory << candidate[:version]
        end
        in_memory
      end
    end
    
    def local_versions(spec, repo)
      path = (spec[:group].split(/\./) + [spec[:id]]).flatten.join('/')
      Dir[File.expand_path(path + "/*", repo)].map { |d| d.pathmap("%f") }.sort.reverse
    end

    def remote_versions(art, base, from = :metadata, fallback = true)
      path = (art[:group].split(/\./) + [art[:id]]).flatten.join('/')
      base ||= "http://mirrors.ibiblio.org/pub/mirrors/maven2"
      uris = {:metadata => "#{base}/#{path}/maven-metadata.xml"}
      uris[:listing] = "#{base}/#{path}/" if base =~ /^https?:/
        xml = nil
      until xml || uris.empty?
        begin
          xml = URI.read(uris.delete(from))
        rescue URI::NotFoundError => e
          from = fallback ? uris.keys.first : nil
        end
      end
      return [] unless xml
      doc = hpricot(xml)
      case from
      when :metadata then
        doc.search("versions/version").map(&:innerHTML).reverse
      when :listing then
        doc.search("a[@href]").inject([]) { |vers, a|
          vers << a.innerHTML.chop if a.innerHTML[-1..-1] == '/'
          vers
        }.sort.reverse
      else 
        fail "Don't know how to parse #{from}: \n#{xml.inspect}"
      end
    end

    def mvnrepository_versions(art)
      uri = "http://www.mvnrepository.com/artifact/#{art[:group]}/#{art[:id]}"
      xml = begin
              URI.read(uri)
            rescue URI::NotFoundError => e
              puts e.class, e
              return []
            end
      doc = hpricot(xml)
      doc.search("table.grid/tr/td[1]/a").map(&:innerHTML)
    end

    def hpricot(xml)
      send :require, 'hpricot'
    rescue LoadError
      cmd = "gem install hpricot"
      if PLATFORM[/java/]
        cmd = "jruby -S " + cmd + " --source http://caldersphere.net"
      end
      raise <<-NOTICE
      Your system is missing the hpricot gem, install it with:
        #{cmd}
      NOTICE
    else
      Hpricot(xml)
    end
  end

  
  class VersionRequirement
    
    CMP_PROCS = Gem::Requirement::OPS.dup
    CMP_REGEX = Gem::Requirement::OP_RE.dup
    CMP_CHARS = CMP_PROCS.keys.join
    BOOL_CHARS = '\|\&\!'
    VER_CHARS = '\w\.'
    
    class << self
      def requirement?(str)
        str[/[#{BOOL_CHARS}#{CMP_CHARS}\(\)]/]
      end
      
      def create(str)
        instance_eval normalize(str)
      rescue StandardError => e
        raise "Failed to parse #{str.inspect} due to: #{e}"
      end

      private
      def requirement(req)
        unless req =~ /^\s*(#{CMP_REGEX})?\s*([#{VER_CHARS}]+)\s*$/
          raise "Invalid requirement string: #{req}"
        end
        comparator, version = $1, $2
        version = Gem::Version.new(0).tap { |v| v.version = version }
        VersionRequirement.new(nil, [$1, version])
      end

      def negate(vreq)
        vreq.negative = !vreq.negative
        vreq
      end
      
      def normalize(str)
        str = str.strip
        if str[/[^\s\(\)#{BOOL_CHARS + VER_CHARS + CMP_CHARS}]/]
          raise "version string contains invalid characters"
        end
        str.gsub!(/\s+(and|\&\&)\s+/, ' & ')
        str.gsub!(/\s+(or|\|\|)\s+/, ' | ')
        str.gsub!(/(^|\s*)not\s+/, ' ! ')
        pattern = /(#{CMP_REGEX})?\s*[#{VER_CHARS}]+/
        left_pattern = /[#{VER_CHARS}\)]$/
        right_pattern = /^(#{pattern}|\()/
        str = str.split.inject([]) do |ary, i|
          ary << '&' if ary.last =~ left_pattern  && i =~ right_pattern
          ary << i
        end
        str = str.join(' ')
        str.gsub!('!', ' negate \1')
        str.gsub!(pattern) do |expr|
          case expr.strip
          when 'not', 'negate' then 'negate '
          else 'requirement("' + expr + '")'
          end
        end
        str.gsub!(/negate\s+\(/, 'negate(')
        str
      end
    end

    def initialize(op, *requirements)
      @op, @requirements = op, requirements
    end

    def has_alternatives?
      requirements.size > 1
    end

    def default
      default = nil
      requirements.reverse.find do |r|
        if Array === r
          if !negative && (r.first.nil? || r.first.include?('='))
            default = r.last.to_s
          end
        else
          default = r.default
        end
      end
      default
    end

    def satisfied_by?(version)
      unless version.kind_of?(Gem::Version)
        version = Gem::Version.new(0).tap { |v| v.version = version }
      end
      message = op == :| ? :any? : :all?
      result = requirements.send message do |req|
        if Array === req
          cmp, rv = *req
          CMP_PROCS[cmp || '='].call(version, rv)
        else
          req.satisfied_by?(version)
        end
      end
      negative ? !result : result
    end

    def |(other)
      operation(:|, other)
    end

    def &(other)
      operation(:&, other)
    end

    def to_s
      str = requirements.map(&:to_s).join(" " + @op.to_s + " ").to_s
      str = "( " + str + " )" if negative || requirements.size > 1
      str = "!" + str if negative
      str
    end

    attr_accessor :negative
    protected
    attr_reader :requirements, :op
    def operation(op, other)
      @op ||= op 
      if negative == other.negative && @op == op && other.requirements.size == 1
        @requirements << other.requirements.first
        self
      else
        self.class.new(op, self, other)
      end
    end
  end

  module ArtifactSearchExtension
    include Extension
    
    def version_requirement(str)
      VersionRequirement.create(str)
    end
    
    def artifact_search_enabled(bool)
      if block_given?
        old = ArtifactSearch.enabled?
        begin
          ArtifactSearch.enabled = bool
          yield
        ensure
          ArtifactSearch.enabled = old
        end
      else
        ArtifactSearch.enabled = bool
      end
    end
  end

  class Project
    include ArtifactSearchExtension
  end

end

