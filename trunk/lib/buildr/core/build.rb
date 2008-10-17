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
      def commit(file, message)
        svn 'commit', '-m', message, file
      end
      
      def copy(dir, url, message)
        svn 'copy', dir, url, '-m', message
      end
      
      # Return the current SVN URL
      def repo_url
        svn('info').scan(/URL: (.*)/)[0][0]
      end
      
      def remove(url, message)
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
        trace cmd
        `#{cmd}`.tap { fail 'SVN command failed' unless $?.exitstatus == 0 }
      end
    end
  end
  
  
  class Release

    THIS_VERSION_PATTERN  = /(THIS_VERSION|VERSION_NUMBER)\s*=\s*(["'])(.*)\2/

    class << self
      
      # Use this to specify a different tag name for tagging the release in source control.
      # You can set the tag name or a proc that will be called with the version number,
      # for example:
      #   Release.tag_name = lambda { |ver| "foo-#{ver}" }
      attr_accessor :tag_name

      # :call-seq:
      #   make()
      #
      # Make a release.
      def make
        check
        with_release_candidate_version do |release_candidate_buildfile| 
          options = ['--buildfile', release_candidate_buildfile, 'DEBUG=no']
          options << '--environment' << Buildr.environment unless Buildr.environment.to_s.empty?
          buildr %w{clean upload}, options
        end
        tag_release
        commit_new_snapshot
      end

      # :call-seq:
      #   extract_version() => this_version
      #
      # Extract the current version number from the buildfile.
      # Raise an error if not found.
      def extract_version
        buildfile = File.read(Buildr.application.buildfile.to_s)
        buildfile.scan(THIS_VERSION_PATTERN)[0][2]
      rescue
        fail 'Looking for THIS_VERSION = "..." in your Buildfile, none found'
      end
      
      # :call-seq:
      #   tag_url(svn_url, version) => tag_url
      #
      # Returns the SVN url for the tag.
      # Can tag from the trunk or from branches.
      # Can handle the two standard repository layouts.
      #   - http://my.repo/foo/trunk => http://my.repo/foo/tags/1.0.0
      #   - http://my.repo/trunk/foo => http://my.repo/tags/foo/1.0.0
      def tag_url(svn_url, version)
        trunk_or_branches = Regexp.union(%r{^(.*)/trunk(.*)$}, %r{^(.*)/branches(.*)/([^/]*)$})
        match = trunk_or_branches.match(svn_url)
        prefix = match[1] || match[3]
        suffix = match[2] || match[4]
        tag = tag_name || version
        tag = tag.call(version) if Proc === tag
        prefix + '/tags' + suffix + '/' + tag
      end
      
      # :call-seq:
      #   check()
      #
      # Check that we don't have any local changes in the working copy. Fails if it finds anything
      # in the working copy that is not checked into source control.
      def check
        fail "SVN URL must contain 'trunk' or 'branches/...'" unless Svn.repo_url =~ /(trunk)|(branches.*)$/
        fail "Uncommitted SVN files violate the First Principle Of Release!\n#{Svn.uncommitted_files}" unless Svn.uncommitted_files.empty?
      end

    protected

      # :call-seq:
      #   buildr(tasks, options)
      #
      # Calls another instance of buildr.
      def buildr(tasks, options)
          sh "#{command} _#{Buildr::VERSION}_ #{tasks.join(' ')} #{options.join(' ')}"
      end
      
      def command #:nodoc:
        Config::CONFIG['arch'] =~ /dos|win32/i ? $PROGRAM_NAME.ext('cmd') : $PROGRAM_NAME
      end

      # :call-seq:
      #   with_release_candidate_version() { |filename| ... }
      #
      # Yields to block with release candidate buildfile, before committing to use it.
      #
      # We need a Buildfile with upgraded version numbers to run the build, but we don't want the
      # Buildfile modified unless the build succeeds. So this method updates the version number in
      # a separate (Buildfile.next) file, yields to the block with that filename, and if successful
      # copies the new file over the existing one.
      #
      # The release version is the current version without '-SNAPSHOT'.  So:
      #   THIS_VERSION = 1.1.0-SNAPSHOT
      # becomes:
      #   THIS_VERSION = 1.1.0
      # for the release buildfile.
      def with_release_candidate_version
        release_candidate_buildfile = Buildr.application.buildfile.to_s + '.next'
        release_candidate_buildfile_contents = change_version { |version| version[-1] = version[-1].to_i }
        File.open(release_candidate_buildfile, 'w') { |file| file.write release_candidate_buildfile_contents }
        begin
          yield release_candidate_buildfile
          mv release_candidate_buildfile, Buildr.application.buildfile.to_s
        ensure
          rm release_candidate_buildfile rescue nil
        end
      end

      # :call-seq:
      #   change_version() { |this_version| ... } => buildfile
      #
      # Change version number in the current Buildfile, but without writing a new file (yet).
      # Returns the contents of the Buildfile with the modified version number.
      #
      # This method yields to the block with the current (this) version number as an array and expects
      # the block to update it.
      def change_version
        this_version = extract_version
        new_version = this_version.split('.')
        yield(new_version)
        new_version = new_version.join('.')
        buildfile = File.read(Buildr.application.buildfile.to_s)
        buildfile.gsub(THIS_VERSION_PATTERN) { |ver| ver.sub(/(["']).*\1/, %Q{"#{new_version}"}) }
      end

      # :call-seq:
      #   tag_release()
      #
      # Tags the current working copy with the release version number.
      def tag_release
        version = extract_version
        info "Tagging release #{version}"
        url = tag_url Svn.repo_url, version
        Svn.remove url, 'Removing old copy' rescue nil
        Svn.copy Dir.pwd, url, "Release #{version}"
      end

      # :call-seq:
      #   commit_new_snapshot()
      #
      # Last, we commit what we currently have in the working copy with an upgraded version number.
      def commit_new_snapshot
        buildfile = change_version { |version| version[-1] = (version[-1].to_i + 1).to_s + '-SNAPSHOT' }
        File.open(Buildr.application.buildfile.to_s, 'w') { |file| file.write buildfile }
        Svn.commit Buildr.application.buildfile.to_s, "Changed version number to #{extract_version}"
        info "Current version is now #{extract_version}"
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
