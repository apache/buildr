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


begin
  require 'rubyforge'
rescue LoadError
  puts 'Please run rake setup to install the RubyForge gem'
  task 'setup' do
    install_gem 'rubyforge'
  end
  task 'release:check' do
    fail 'Please run rake setup to install the RubyForge gem'
  end
end


namespace 'release' do
 
  # This task does all prerequisites checks before starting the release, for example,
  # that we have Groovy and Scala to run all the test cases, or that we have Allison
  # and PrinceXML to generate the full documentation.
  task 'check'=>'setup'
  # This task does all the preparation work before making a release and also checks
  # that we generate all the right material, for example, that we compiled Java sources,
  # created the PDF, have coverage report.
  task 'prepare'=>['clobber', 'check']

  # Does CHANGELOG reflects current release?
  task 'check' do
    print 'Checking that CHANGELOG indicates most recent version and today\'s date ... '
    expecting = "#{spec.version} (#{Time.now.strftime('%Y-%m-%d')})"
    header = File.readlines('CHANGELOG').first.chomp
    fail "Expecting CHANGELOG to start with #{expecting}, but found #{header} instead" unless expecting == header
    puts 'OK'
  end

  # No local changes.
  task 'check' do
    print 'Checking there are no local changes ... '
    status = `svn status`
    fail "Cannot release unless all local changes are in SVN:\n#{status}" unless status.empty?
    fail "Cannot release unless all local changes are in Git:\n" + `git status` if `git status`[/^#\t/]
    puts 'OK'
  end

  desc 'Make a release'
  task 'make'=>'release:prepare' do |task|
    task.enhance do
      task('release:wrapup').invoke
    end
  end

  task 'rubyforge'=>'package' do
    if File.exist?('CHANGELOG')
      # Read the changes for this release.
      print 'Looking for changes between this release and previous one ... '
      pattern = /(^(\d+\.\d+(?:\.\d+)?)\s+\(\d{4}-\d{2}-\d{2}\)\s*((:?^[^\n]+\n)*))/
      changes = File.read('CHANGELOG').scan(pattern).inject({}) { |hash, set| hash[set[1]] = set[2] ; hash }
      current = changes[spec.version.to_s]
      current = changes[spec.version.to_s.split('.')[0..-2].join('.')] if !current && spec.version.to_s =~ /\.0$/
      fail "No changeset found for version #{spec.version}" unless current
      puts 'OK'
    end

    print "Uploading #{spec.version} to RubyForge ... "
    files = Dir.glob('pkg/*.{gem,tgz,zip}')
    rubyforge = RubyForge.new
    rubyforge.login 
    begin
      if changes
        File.open('.changes', 'w'){|f| f.write(current)}
        rubyforge.userconfig.merge!('release_changes' => '.changes',  'preformatted' => true)
      end
      rubyforge.add_release spec.rubyforge_project.downcase, spec.name.downcase, spec.version, *files
    ensure
      rm '.changes' if changes
    end
    puts 'Done'
  end

  # Tag this release in SVN.
  task 'tag' do
    info = `svn info` + `git svn info` # Using either svn or git-svn
    url = info[/^URL:/] && info.scan(/^URL: (.*)/)[0][0] 
    break unless url
    new_url = url.sub(/(trunk$)|(branches\/\w*)$/, "tags/#{spec.version}")
    break if url == new_url
    print "Tagging release as tags/#{spec.version} ... "
    sh 'svn', 'copy', url, new_url, '-m', "Release #{spec.version}", :verbose=>false do |ok, res|
      if ok
        puts 'Done'
      else
        puts 'Could not create tag, please do it yourself!'
        puts %{  svn copy #{url} #{new_url} -m "#{spec.version}"}
      end
    end
  end

  # Update lib/buildr.rb to next vesion number, add new entry in CHANGELOG.
  task 'next_version'=>'tag' do
    next_version = spec.version.to_ints.zip([0, 0, 1]).map { |a| a.inject(0) { |t,i| t + i } }.join('.')
    ver_file = "lib/#{spec.name}.rb"
    if File.exist?(ver_file)
      print "Updating #{ver_file} to next version number (#{next_version}) ... "
      modified = File.read(ver_file).sub(/(VERSION\s*=\s*)(['"])(.*)\2/) { |line| "#{$1}#{$2}#{next_version}#{$2}" } 
      File.open(ver_file, 'w') { |file| file.write modified }
      puts 'Done'
    end

    if File.exist?('CHANGELOG')
      print 'Adding new entry to CHANGELOG ... '
      modified = "#{next_version} (Pending)\n\n" + File.read('CHANGELOG')
      File.open('CHANGELOG', 'w') { |file| file.write modified }
      puts 'Done'
    end
  end

  task 'wrapup'=>['tag', 'next_version']

end
