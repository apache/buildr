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


require 'buildr/core/package'
require 'buildr/tasks/zip'
$LOADED_FEATURES << 'rubygems/open-uri.rb' # We already have open-uri, RubyGems loads a different one
require 'rubygems/source_info_cache'
require 'rubygems/doc_manager'
require 'rubygems/format'
require 'rubyforge'


module Buildr

  # :call-seq:
  #   addon(name, version?)
  #   addon(task)
  #
  # Use the specified addon, downloading and install it, if necessary.
  #
  # Addons are essentially Ruby gems, but installed and loaded differently:
  # * The addon method downloads and installs the gem, if necessary.
  # * It requires a Ruby file with the same name as the gem, if it finds one.
  # * It imports all .rake files found in the Gem's tasks directory.
  #
  # The first form takes the gem's name and optional version requirement.  The default
  # version requirement is '>= 0' (see RubyGem's gem method for more information).
  # For example:
  #   addon 'buildr-java', '~> 1.0'
  #
  # The second form takes a file task that points to the Gem file.
  def addon(name_or_path, version = nil)
    case name_or_path
    when Rake::FileTask
      path = name_or_path.to_s
      spec = Gem::Format.from_file_by_path(path).spec
    when String
      dep = Gem::Dependency.new(name_or_path, version)
      #spec = Gem::SourceIndex.from_installed_gems.search(dep).last || Gem::SourceInfoCache.search(dep).last
      unless spec = Gem::SourceIndex.from_installed_gems.search(dep).last
        Gem::SourceInfoCache.search(dep).last
        Gem::SourceInfoCache.cache.flush
        fail Gem::LoadError, "Could not find #{name_or_path} locally or in remote repository." unless spec
      end
    else fail "First argument must be Gem name or File task."
    end

    if Gem::SourceIndex.from_installed_gems.search(spec.name, spec.version).empty?
      say "Installing #{spec.full_name} ... " if verbose
      cmd = Config::CONFIG['ruby_install_name'], '-S', 'gem', 'install', name_or_path.to_s
      cmd << '-v' << spec.version.to_s
      cmd.unshift 'sudo' unless Gem.win_platform? || RUBY_PLATFORM =~ /java/
      sh *cmd.push(:verbose=>false)
      Gem.source_index.load_gems_in Gem::SourceIndex.installed_spec_directories
      # NOTE:  The nice thing would be to do a Gem install from the process,
      #        but installing the documenation requires RDoc, and RDoc defines
      #        one too many top-level classes which mess with our stuff.
=begin
      require 'rubygems/dependency_installer'
      installer = Gem::DependencyInstaller.new(path || name, version.to_s).tap do |installer|
        installer.install 
        say 'Installed'
        installer.installed_gems.each do |spec|
          # NOTE:  RI documentation must be generated before RDoc.
          Gem::DocManager.new(spec, nil).generate_ri
          Gem::DocManager.new(spec, nil).generate_rdoc
          Gem.source_index.add_spec spec
        end
      end
=end
    end
    
    Gem.activate(spec.name, true, spec.version).tap do
      FileList[spec.require_paths.map { |path| File.expand_path("#{path}/*.rb", spec.full_gem_path) }].
        map { |path| File.basename(path) }.each { |file| require file }
      FileList[File.expand_path('tasks/*.rake', spec.full_gem_path)].each do |file|
        Rake.application.add_import file
      end
    end
  end


  class PackageGemTask < ArchiveTask

    def initialize(*args)
      super
      @spec = Gem::Specification.new
    end

    def spec
      yield @spec if block_given?
      @spec
    end

    def install
      cmd = Config::CONFIG['ruby_install_name'], '-S', 'gem', 'install', name
      cmd .unshift 'sudo' unless Gem.win_platform? || RUBY_PLATFORM =~ /java/
      sh *cmd
    end

    def uninstall
      cmd = Config::CONFIG['ruby_install_name'], '-S', 'gem', 'uninstall', spec.name, '-v', spec.version.to_s
      cmd .unshift 'sudo' unless Gem.win_platform? || RUBY_PLATFORM =~ /java/
      sh *cmd
    end

    def upload
      rubyforge = RubyForge.new
      rubyforge.login
      #File.open('.changes', 'w'){|f| f.write(current)}
      #rubyforge.userconfig.merge!('release_changes' => '.changes',  'preformatted' => true)
      rubyforge.add_release spec.rubyforge_project.downcase, spec.name.downcase, spec.version, package(:gem).to_s
    end

  private

    def create_from(file_map)
      spec.mark_version
      spec.validate
      Gem::Package.open(name, 'w', signer) do |pkg|
        pkg.metadata = spec.to_yaml
        file_map.each do |path, content|
          next if content.nil? || File.directory?(content.to_s)
          pkg.add_file_simple(path, File.stat(name).mode & 0777, File.size(content.to_s)) do |os|
              os.write File.open(content.to_s, 'rb') { |f| f.read }
          end
        end
      end
    end

    def signer
      # TODO: implement.
    end
  end


  module PackageAsGem

    def package_as_gem(file_name) #:nodoc:
      PackageGemTask.define_task(file_name).tap do |gem|
        %{ lib test doc }.each do |dir|
          gem.include :from=>_(dir), :path=>dir if File.directory?(_(dir))
        end
        gem.spec do |spec|
          spec.name = id
          spec.version = version
          spec.summary = full_comment
          spec.has_rdoc = true
          spec.rdoc_options << '--title' << comment
          spec.require_path = 'lib'
        end
      end
    end

  end

  class Project
    include PackageAsGem
  end

end
