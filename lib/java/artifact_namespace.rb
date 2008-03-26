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

  #
  # ArtifactNamespace allows users to control artifact versions to be
  # used by their projects and Buildr modules/addons.
  # 
  # A namespace is a hierarchical dictionary that allows to specify
  # artifact version requirements (see ArtifactNamespace#need).
  #
  # Every project can have it's own namespace inheriting the one for
  # their parent projects. 
  #
  # To open the namespace for the current context just provide a block
  # to the Buildr.artifacts method (see ArtifactNamespace.instance):
  #
  #    -- buildfile --
  #    # open the root namespace, equivalent to +artifacts.namespace(nil)+
  #    artifacts do |ns|
  #       # later referenced by name
  #       ns.use :spring => 'org.springframework:spring:jar:2.5'
  #       ns.use :log4j => 'log4j:log4j:jar:1.2.15'
  #    end
  #
  #    require 'buildr/xmlbeans'
  #    # specify the xmlbeans version to use:
  #    artifacts[Buildr::XMLBeans][:xmlbeans] = '2.2'
  #   
  #    # select some artifacts by their ruby symbols or spec
  #    define 'foo_proj' { compile.with :log4j, :'asm:asm:jar:-', 'some:other:jar:2.0' }
  #    # or get all used artifacts for the project namespace
  #    define 'bar_proj' { compile.with artifacts[self].used }
  # 
  # The ArtifactNamespace.load method can be used to populate your
  # namespaces from a hash of hashes, like your profile yaml in the
  # following example:
  # 
  #   -- profiles.yaml --
  #   development:
  #     artifacts:
  #       # root namespace, null name
  #       ~:
  #         spring:     org.springframework:spring:jar:2.5
  #         log4j:      log4j:log4j:jar:1.2.15
  #         groovy:     org.codehaus.groovy:groovy:jar:1.5.4
  #       
  #       # module/addon namespace
  #       Buildr::XMLBeans: 
  #         xmlbeans: 2.2
  #
  #       # for subproject one:oldie
  #       one:oldie:
  #         spring:  org.springframework:spring:jar:1.0
  #
  #   -- buildfile --
  #   ArtifactNamespace.load(Buildr.profile['artifacts'])
  #   require 'buildr/xmlbeans' # will use xmlbeans-2.2
  #   require 'java/groovyc' # will find groovy 1.5.4 on global ns
  #   describe 'one' do 
  #     compile.with :spring, :log4j   # spring-2.5, log4j-1.2.15
  #     describe 'oldie' do
  #       compile.with :spring, :log4j # spring-1.0, log4j-1.2.15
  #     end
  #   end
  # 
  # 
  class ArtifactNamespace
    
    # Mixin for arrays returned by Buildr.artifacts
    module AryMixin
      
      # :call-seq:
      #   artifacts[numeric] -> artifact
      #   artifacts[scope] -> namespace
      #
      # Extends the regular Array#[] so that non numeric
      # indices are scope names, returning the corresponding
      # namespace
      def [](idx)
        if Numeric === idx
          super
        else
          namespace(idx)
        end
      end
      
      # :call-seq:
      #   artifacts.namespace -> namespace
      #   artifacts.namespace(scope) -> namespace
      def namespace(*a, &b)
        ArtifactNamespace.instance(*a, &b)
      end
      
      alias_method :ns, :namespace
    end
    
    ROOT = :root

    class << self
      # Populate namespaces from a hash of hashes. 
      # The following example uses the profiles yaml to achieve this.
      #
      #   -- profiles.yaml --
      #   development:
      #     artifacts:
      #       # root namespace, null name
      #       ~:
      #         spring:     org.springframework:spring:jar:2.5
      #         log4j:      log4j:log4j:jar:1.2.15
      #         groovy:     org.codehaus.groovy:groovy:jar:1.5.4
      #       
      #       # open Buildr::XMLBeans namespace
      #       Buildr::XMLBeans:
      #         xmlbeans: 2.2
      #
      #       # for subproject one:oldie
      #       one:oldie:
      #         spring:  org.springframework:spring:jar:1.0
      #
      #   -- buildfile --
      #   ArtifactNamespace.load(Buildr.profile['artifacts'])
      def load(namespace_hash)
        if Hash === namespace_hash
          namespace_hash.each_pair do |name, uses|
            instance(name).use(uses)
          end
        end
      end
      
      # Forget all previously declared namespaces.
      def clear 
        @instances = nil
      end

      # :call-seq:
      #   Buildr.artifacts { |ns| ... } -> namespace
      #   Buildr.artifacts(scope) { |ns| ... } -> namespace
      # 
      # Obtain the namespace for the given +scope+ or for the currently
      # running project. If a block is given, the namespace is yielded to it.
      def instance(name = nil, &block)
        case name
        when Array then name = name.join(':')
        when Module, Project then name = name.name
        when nil then
          task = Thread.current[:rake_chain]
          task = task.instance_variable_get(:@value) if task
          name = task ? task.scope : Rake.application.current_scope
          name = name.join(':')
        end
        name = name.to_s.split(/:{2,}/).join(':')
        name = ROOT if name.to_s.blank?
        @instances ||= Hash.new { |h, k| h[k] = new(k) }
        instance = @instances[name.to_sym]
        instance.tap(&block) if block
        instance
      end
      
      alias_method :for, :instance
    end

    def initialize(name) #:nodoc:
      @name = name
      clear
    end

    attr_reader :name
    include Enumerable
    
    # Return an array of artifacts defined for use
    def to_a(include_parents = false)
      seen = {}
      registry = self
      while registry
        registry.instance_variable_get(:@using).each_pair do |key, spec|
          spec = spec(key) unless Hash == spec
          name = Artifact.to_spec(spec.merge(:version => '-'))
          seen[name] = Buildr.artifact(spec) unless seen.key?(name)
        end
        registry = include_parents ? registry.parent : nil
      end
      seen.values
    end

    def each(&block)
      to_a.each(&block)
    end

    
    # Set the parent namespace
    def parent=(parent)
      fail "Cannot set parent of root namespace!" if @name == ROOT
      @parent = parent
    end

    # :call-seq:
    #   namespace.parent { |parent_namespace| ... } -> parent_namespace
    # 
    # Get the parent namespace
    def parent(&block)
      return nil if @name == ROOT
      if @parent
        @parent = self.class.instance(@parent) unless @parent.kind_of?(self.class)
      else
        name = @name.to_s.split(':')[0...-1].join(':')
        @parent = self.class.instance(name)
      end
      @parent.tap(&block)
    end
    
    # Clear internal requirements map
    def clear
      @using = {}
      @aliases = {}
      @requires = {}
    end
    

    # Return the named artifacts from this namespace hierarchy
    def only(*names)
      names = @requires.keys if names.empty?
      ary = names.map { |name| Buildr.artifact(spec(name)) }
      ary.size == 1 ? ary.first : ary
    end

    # Test if named requirement has been satisfied
    def satisfied?(name)
      req, spec = requirement(name), spec(name)
      if req && spec
        req[:version].satisfied_by?(spec[:version])
      else
        false
      end
    end

    # Return the artifact spec (a hash) for the given name
    def spec(name)
      name = normalize_name(name)
      using = @using[name] || @using[@aliases[name]]
      if using
        if using.kind_of?(Hash)
          spec = using.dup
        else
          spec = @requires[name] || @requires[@aliases[name]]
          spec = spec ? spec.dup : {}
          spec[:version] = using.dup
        end
        spec
      elsif parent
        parent.spec(name) || parent.spec(@aliases[name])
      end
    end

    def requirement(name)
      name = normalize_name(name)
      req = @requires[name] || @requires[@aliases[name]]
      if req
        req.dup
      elsif parent
        parent.requirement(name)
      end
    end

    def delete(name)
      name = normalize_name(name)
      [name, @aliases[name]].each do |n|
        @requires.delete(n); @using.delete(n); @aliases.delete(n)
      end
      self
    end

    # :call-seq: 
    #   artifacts do
    #     need *specs
    #     need name => spec
    #   end
    # 
    # Establish an artifact dependency on the current namespace.
    # A dependency is simply an artifact spec whose version part
    # contains comparision operators.
    #
    # Supported comparison operators are =, !=, >, <, >=, <= and ~>.
    # The compatible comparison (~>) matches from the specified version up one version.
    # For example, ~> 5.3.1 will match all versions from 5.3.1 up to but excluding 5.4,
    # while ~> 5.3 will match all versions from 5.3.0 up to but excluding 6.
    #
    # In adition to comparition operators, artifact requirements support logic operators
    # 
    # * ( expr )     -- expression grouping
    # * !( expr )    -- negate nested expr, parens are required
    # * expr & expr  -- Logical and
    # * expr |  expr -- Logical or
    #
    # Requirements defined on parent namespaces, are inherited by
    # their childs, this means that when a specific version is selected for use
    # on a sub-namespace, validation will be performed by checking the parent requirement.
    #
    #   artifacts('one') do 
    #     need :bar => 'foo:bar:jar:1.0 | ~>1.0'
    #     need 'foo:baz:jar:>1.2 & <1.3 & !(>=1.2.5 | <=1.2.6)'
    #     # default logical operator is &, so this can be written as
    #     need 'foo:baz:jar:>1.2 <1.3 !(>=1.2.5 | <=1.2.6)'
    #   end
    # 
    #   artifacts('one:two') do 
    #     use :bar => '0.9' # This wil fail because of previous requirement
    #     use :bar => '1.1.1' # valid, selected for usage
    #
    #     use 'foo:baz:jar:1.2.5.1' # on invalid range
    #     use 'foo:bar:jar:1.2.4' # valid, selected for usage
    #
    #     use :bat => 'foo:bat:jar:0.9' # valid, no requirement found for it
    #   end
    def need(*specs)
      specs.flatten.each do |spec|
        named = {}
        if (Hash === spec || Struct === spec) &&
           (spec.keys & ActsAsArtifact::ARTIFACT_ATTRIBUTES).empty?
          spec.each_pair { |k, v| named[k] = Artifact.to_hash(v) }
        else
          named[nil] = Artifact.to_hash(spec)
        end
        named.each_pair do |name, spec|
          spec[:version] = VersionRequirement.create(spec[:version])
          unvers = Artifact.to_spec(spec.merge(:version => '-')).to_sym
          @requires[unvers] = spec
          if name
            name = name.to_sym
            using = @using[name] || @using[@aliases[name]]
            using = { :version  => using } if using.kind_of?(String) && VersionRequirement.version?(using)
            fail_unless_satisfied(spec, using)
            @aliases[name.to_sym] = unvers
            @aliases[unvers] = name.to_sym
          end
        end
      end
      self
    end

    # Specify default version if no previous one has been selected.
    # This method is useful mainly for plugin/addon writers, allowing
    # their users to override the artifact version to be used.
    # Plugin/Addon writers need to document the +scope+ used by their
    # addon, which can be simply an string or a module name.
    # 
    # Suppose we are writing the Foo::Addon module
    #
    #   module Foo::Addon
    #     artifacts(self) do # scope is the module name => "Foo::Addon"
    #       need :bar => 'foo:bar:jar:>2.0', # suppose bar is used at load time
    #            :baz => 'foo:baz:jar:>3.0'  # used when Foo::Addon.baz called
    #       default :bar => '2.5', :baz => '3.5'
    #     end
    #   end
    #
    #   # If the artifact is used at load time, users would
    #   # need to select versions before loading the addon.
    #   artifacts('Foo::Addon') do 
    #     use :bar => '3.1'
    #   end
    #   # load the addon
    #   addon 'foo_addon' # used bar-3.1 not 2.5
    #   Foo::Addon.baz    # used baz-3.5
    #   artifacts.namespace('Foo::Addon').use :baz => '4.0'
    #   Foo::Addon.baz    # used baz-4.0
    # 
    def default(*specs)
      @setting_defaults = true
      begin
        use(*specs)
      ensure
        @setting_defaults = false
      end
    end

    # See examples for #need and #default methods.
    def use(*specs)
      specs.flatten.each do |spec|
        if (Hash === spec || Struct === spec) &&
           (spec.keys & ActsAsArtifact::ARTIFACT_ATTRIBUTES).empty?
          spec.each_pair do |k, v|
            if VersionRequirement.version?(v)
              set(k, v)
            else
              spec = Artifact.to_hash(v)
              set(k, spec)
            end
          end
        else
          set(spec, Artifact.to_hash(spec))
        end
      end
      self
    end
    
    alias_method :<<, :use
    alias_method :[], :only
    
    # :call-seq:
    #   artifacts.namespace('foo:bar')[:commons_net] = '1.0'
    # 
    # Selects an artifact version for usage, with hash like syntax.
    # 
    # Alias for #use
    def []=(name, spec)
      use name => spec
    end

    private
    def normalize_name(name)
      if name.to_s =~ /([^:]+:){2,4}/ 
        spec = Artifact.to_hash(name.to_s)
        Artifact.to_spec(spec.merge(:version => '-')).to_sym
      elsif name.kind_of?(Symbol) || name.kind_of?(String)
        name.to_sym
      else
        spec = Artifact.to_hash(name)
        Artifact.to_spec(spec.merge(:version => '-')).to_sym
      end
    end
    
    def fail_unless_satisfied(req, spec)
      if req && spec
        spec = spec.dup
        version = spec[:version]
        unless req[:version].satisfied_by?(version)
          raise "Version requirement #{Artifact.to_spec(req)} " +
            "not met by #{version}"
        end
        spec.delete(:version)
        if !spec.empty? && req.values_at(*spec.keys) != spec.values_at(*spec.keys)
          spec[:version] = version
          raise "Artifact attributes mismatch, " + 
            "required #{Artifact.to_spec(req)}, got #{Artifact.to_spec(spec)}"
        end
      end
    end

    def set(name, spec)
      name = normalize_name(name)
      needed = requirement(name)
      candidate = VersionRequirement.version?(spec) ? {:version => spec } : spec
      if @setting_defaults
        current = spec(name)
        satisfied = current && needed && needed[:version].satisfied_by?(current[:version])
        unless satisfied || (!needed && current)
          fail_unless_satisfied(needed, candidate)
          @using[name] = spec
        end
      else
        fail_unless_satisfied(needed, candidate)
        @using[name] = spec
      end
    end

  end # ArtifactNamespace

  class VersionRequirement
    
    CMP_PROCS = Gem::Requirement::OPS.dup
    CMP_REGEX = Gem::Requirement::OP_RE.dup
    CMP_CHARS = CMP_PROCS.keys.join
    BOOL_CHARS = '\|\&\!'
    VER_CHARS = '\w\.'
    
    class << self
      def version?(str)
        /^\s*[#{VER_CHARS}]+\s*$/ === str
      end
      
      def requirement?(str)
        /[#{BOOL_CHARS}#{CMP_CHARS}\(\)]/ === str
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
          raise "version string #{str.inspect} contains invalid characters"
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
      return false unless version
      unless version.kind_of?(Gem::Version)
        raise "Invalid version: #{version.inspect}" unless self.class.version?(version)
        version = Gem::Version.new(0).tap { |v| v.version = version.strip }
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
  end # VersionRequirement

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
  end # Search

end

