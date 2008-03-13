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


require 'core/package'
require 'tasks/zip'
$LOADED_FEATURES << 'rubygems/open-uri.rb' # We already have open-uri, RubyGems loads a different one
require 'rubygems/source_info_cache'
require 'rubygems/doc_manager'
require 'rubygems/format'
require 'rubyforge'


module Buildr

  # :call-seq:
  #   addon(id, options?)
  #   addon(task, options?)
  #
  # Use this to download and install an addon.  The first form takes the addon identifier,
  # a string that contains the qualified name, colon and version number.  For example:
  #   addon 'buildr-openjpa', '1.0'
  # Some addon accept options passed as a hash argument.
  #
  # The second form takes a file task that points to the directory containing the addon.
  def addon(name_or_path, version = nil)
    case name_or_path
    when Rake::FileTask
      path = name_or_path.to_s
      spec = Gem::Format.from_file_by_path(path).spec
      name, version = spec.name, spec.version
    when String
      name = name_or_path
      spec = Gem::SourceIndex.from_installed_gems.search(name, version).first || Gem::SourceInfoCache.search(name, version).first
      fail "Could not find #{name} locally or in remote repository." unless spec
      version ||= '> 0'
    else fail "First argument must be Gem name or File task."
    end

    if Gem::SourceIndex.from_installed_gems.search(name, version).empty?
      say "Installing #{spec.full_name} ... "
      cmd = File.join(Config::CONFIG['bindir'], Config::CONFIG['ruby_install_name']), '-S', 'gem', 'install', name_or_path.to_s
      cmd << '-v' << version.to_s if version
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
    
    Gem.activate(name, true, version).tap do
      spec = Gem.loaded_specs[name]
      FileList[spec.require_paths.map { |path| File.expand_path("#{path}/*.rb", spec.full_gem_path) }].
        map { |path| File.basename(path) }.each { |file| require file }
      FileList[File.expand_path('tasks/*.rake', spec.full_gem_path)].each do |file| 
        Rake.application.add_import
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
        { 'lib' =>_(:source, :main, :ruby),
          'test'=>_(:source, :test, :ruby),
          'doc' =>_(:source, :doc) }.
          each { |target, source| gem.include :from=>source, :path=>target if File.directory?(source) }
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
