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


# Handling of source control.
namespace 'scm' do

  task 'check' do
    print 'Checking there are no local changes ... '
    svn = `svn status`
    fail "Cannot release unless all local changes are in SVN:\n#{svn}" unless svn.empty?
    git = `git status`
    fail "Cannot release unless all local changes are in Git:\n#{git}" if git[/^#\t/]
    puts 'OK'
  end

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

end

task 'stage:check'=>'scm:check'
task 'release:wrapup'=>'scm:tag'
