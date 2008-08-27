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


require 'buildr/core/project'
require 'buildr/core/common'
require 'buildr/core/checks'
require 'buildr/core/environment'


module Buildr

  class Options

    # Runs the build in parallel when true (defaults to false). You can force a parallel build by
    # setting this option directly, or by running the parallel task ahead of the build task.
    #
    # This option only affects recursive tasks. For example:
    #   buildr parallel package
    # will run all package tasks (from the sub-projects) in parallel, but each sub-project's package
    # task runs its child tasks (prepare, compile, resources, etc) in sequence.
    attr_accessor :parallel

  end

  task('parallel') { Buildr.options.parallel = true }


  module Build

    include Extension

    first_time do
      desc 'Build the project'
      Project.local_task('build') { |name| "Building #{name}" }
      desc 'Clean files generated during a build'
      Project.local_task('clean') { |name| "Cleaning #{name}" }

      desc 'The default task is build'
      task 'default'=>'build'
    end

    before_define do |project|
      project.recursive_task 'build'
      project.recursive_task 'clean'
      project.clean do
        verbose(true) do
          rm_rf project.path_to(:target)
          rm_rf project.path_to(:reports)
        end
      end
    end


    # *Deprecated:* Use +path_to(:target)+ instead.
    def target
      Buildr.application.deprecated 'Use path_to(:target) instead'
      layout.expand(:target)
    end

    # *Deprecated:* Use Layout instead.
    def target=(dir)
      Buildr.application.deprecated 'Use Layout instead'
      layout[:target] = _(dir)
    end

    # *Deprecated:* Use +path_to(:reports)+ instead.
    def reports()
      Buildr.application.deprecated 'Use path_to(:reports) instead'
      layout.expand(:reports)
    end

    # *Deprecated:* Use Layout instead.
    def reports=(dir)
      Buildr.application.deprecated 'Use Layout instead'
      layout[:reports] = _(dir)
    end

    # :call-seq:
    #    build(*prereqs) => task
    #    build { |task| .. } => task
    #
    # Returns the project's build task. With arguments or block, also enhances that task.
    def build(*prereqs, &block)
      task('build').enhance prereqs, &block
    end

    # :call-seq:
    #    clean(*prereqs) => task
    #    clean { |task| .. } => task
    #
    # Returns the project's clean task. With arguments or block, also enhances that task.
    def clean(*prereqs, &block)
      task('clean').enhance prereqs, &block
    end

  end


  class Svn

    class << self
      def commit file, message
        svn 'commit', '-m', message, file
      end
      
      def copy dir, url, message
        svn 'copy', dir, url, '-m', message
      end
      
      # Return the current SVN URL
      def repo_url
        url = svn('info').scan(/URL: (.*)/)[0][0]
      end
      
      def remove url, message
        svn 'remove', url, '-m', message
      end
      
      # Status check reveals modified files, but also SVN externals which we can safely ignore.
      def uncommitted_files
        svn('status', '--ignore-externals').reject { |line| line =~ /^X\s/ }
      end
      
      # :call-seq:
      #   svn(*args)
      #
      # Executes SVN command and returns the output.
      def svn(*args)
        cmd = 'svn ' + args.map { |arg| arg[' '] ? %Q{"#{arg}"} : arg }.join(' ')
        info cmd
        `#{cmd}`.tap { fail 'SVN command failed' unless $?.exitstatus == 0 }
      end
    end
  end
  
  
  class Release

    THIS_VERSION_PATTERN  = /(THIS_VERSION|VERSION_NUMBER)\s*=\s*(["'])(.*)\2/
    NEXT_VERSION_PATTERN  = /NEXT_VERSION\s*=\s*(["'])(.*)\1/

    class << self

      # :call-seq:
      #   make()
      #
      # Make a release.
      def make()
        check
        version = with_next_version do |filename| 
          options = ['--buildfile', filename, 'DEBUG=no']
          options << '--environment' << Buildr.environment unless Buildr.environment.to_s.empty?
          sh "#{command} _#{Buildr::VERSION}_ clean upload #{options.join(' ')}"
        end
        tag version
        commit version + '-SNAPSHOT'
      end

      # :call-seq:
      #   extract_versions(buildfile) => this_version, next_version
      #
      # Extract the current and next version numbers from a buildfile.
      # Raise an error if not found.
      def extract_versions buildfile
        begin
          this_version = buildfile.scan(THIS_VERSION_PATTERN)[0][2]
        rescue
          fail 'Looking for THIS_VERSION = "..." in your Buildfile, none found'
        end
        begin
          next_version = buildfile.scan(NEXT_VERSION_PATTERN)[0][1]
        rescue
          fail 'Looking for NEXT_VERSION = "..." in your Buildfile, none found'
        end
        [this_version, next_version]
      end
      
      # :call-seq:
      #   tag_url(svn_url, version) => tag_url
      #
      # Returns the SVN url for the tag.
      # Can tag from the trunk or from branches.
      # Can handle the two standard repository layouts.
      #   - http://my.repo/foo/trunk => http://my.repo/foo/tags/1.0.0
      #   - http://my.repo/trunk/foo => http://my.repo/tags/foo/1.0.0
      def tag_url svn_url, version
        trunk_or_branches = Regexp.union(%r{^(.*)/trunk(.*)$}, %r{^(.*)/branches(.*)/([^/]*)$})
        match = trunk_or_branches.match(svn_url)
        prefix = match[1] || match[3]
        suffix = match[2] || match[4]
        prefix + '/tags' + suffix + '/' + version
      end
      
      # :call-seq:
      #   check()
      #
      # Check that we don't have any local changes in the working copy. Fails if it finds anything
      # in the working copy that is not checked into source control.
      def check()
        fail "SVN URL must contain 'trunk' or 'branches/...'" unless Svn.repo_url =~ /(trunk)|(branches.*)$/
        fail "Uncommitted SVN files violate the First Principle Of Release!\n#{Svn.uncommitted_files}" unless Svn.uncommitted_files.empty?
      end

    protected

      def command() #:nodoc:
        Config::CONFIG['arch'] =~ /dos|win32/i ? $PROGRAM_NAME.ext('cmd') : $PROGRAM_NAME
      end

      # :call-seq:
      #   with_next_version() { |filename| ... } => version
      #
      # Yields to block with upgraded version number, before committing to use it. Returns the *new*
      # current version number.
      #
      # We need a Buildfile with upgraded version numbers to run the build, but we don't want the
      # Buildfile modified unless the build succeeds. So this method updates the version numbers in
      # a separate (Buildfile.next) file, yields to the block with that filename, and if successful
      # copies the new file over the existing one.
      #
      # Version numbers are updated as follows. The next release version becomes the current one,
      # and the next version is upgraded by one to become the new next version. So:
      #   THIS_VERSION = 1.1.0
      #   NEXT_VERSION = 1.2.0
      # becomes:
      #   THIS_VERSION = 1.2.0
      #   NEXT_VERSION = 1.2.1
      # and the method will return 1.2.0.
      def with_next_version()
        new_filename = Buildr.application.buildfile.to_s + '.next'
        modified = change_version do |this_version, next_version|
          one_after = next_version.split('.')
          one_after[-1] = one_after[-1].to_i + 1
          [ next_version, one_after.join('.') ]
        end
        File.open(new_filename, 'w') { |file| file.write modified }
        begin
          yield new_filename
          mv new_filename, Buildr.application.buildfile.to_s
        ensure
          rm new_filename rescue nil
        end
        extract_versions(File.read(Buildr.application.buildfile.to_s))[0]
      end

      # :call-seq:
      #   change_version() { |this, next| ... } => buildfile
      #
      # Change version numbers in the current Buildfile, but without writing a new file (yet).
      # Returns the contents of the Buildfile with the modified version numbers.
      #
      # This method yields to the block with the current (this) and next version numbers and expects
      # an array with the new this and next version numbers.
      def change_version()
        buildfile = File.read(Buildr.application.buildfile.to_s)
        this_version, next_version = extract_versions buildfile
        this_version, next_version = yield(this_version, next_version)
        if verbose
          puts 'Upgrading version numbers:'
          puts "  This:  #{this_version}"
          puts "  Next:  #{next_version}"
        end
        buildfile.gsub(THIS_VERSION_PATTERN) { |ver| ver.sub(/(["']).*\1/, %Q{"#{this_version}"}) }.
          gsub(NEXT_VERSION_PATTERN) { |ver| ver.sub(/(["']).*\1/, %Q{"#{next_version}"}) }
      end

      # :call-seq:
      #   tag(version)
      #
      # Tags the current working copy with the release version number.
      def tag(version)
        url = tag_url Svn.repo_url, version
        Svn.remove url, 'Removing old copy' rescue nil
        Svn.copy Dir.pwd, url, "Release #{version}"
      end

      # :call-seq:
      #   commit(version)
      #
      # Last, we commit what we currently have in the working copy.
      def commit(version)
        buildfile = File.read(Buildr.application.buildfile.to_s).
          gsub(THIS_VERSION_PATTERN) { |ver| ver.sub(/(["']).*\1/, %Q{"#{version}"}) }
        File.open(Buildr.application.buildfile.to_s, 'w') { |file| file.write buildfile }
        Svn.commit Buildr.application.buildfile.to_s, "Changed version number to #{version}"
      end
    end
  end

  
  desc 'Make a release'
  task 'release' do |task|
    Release.make
  end

end


class Buildr::Project
  include Buildr::Build
end
