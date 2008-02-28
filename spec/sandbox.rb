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


# The local repository we use for testing is void of any artifacts, which will break given
# that the code requires several artifacts. So we establish them first using the real local
# repository and cache these across test cases.
repositories.remote << 'http://repo1.maven.org/maven2'
Java.load # Anything added to the classpath.
artifacts(TestFramework.frameworks.map(&:dependencies).flatten).each { |a| file(a).invoke }
task('buildr:initialize').invoke

# We need to run all tests inside a sandbox, tacking a snapshot of Rake/Buildr before the test,
# and restoring everything to its previous state after the test. Damn state changes.
module Sandbox

  def self.included(spec)
    spec.before(:each) { sandbox }
    spec.after(:each) { reset }
  end

  def sandbox
    @sandbox = {}
    # During teardown we get rid of all the tasks and start with a clean slate.
    # Unfortunately, we also get rid of tasks we need, like build, clean, etc.
    # Here we capture them in their original form, recreated during teardown.
    @sandbox[:tasks] = Rake.application.tasks.collect do |original|
      prerequisites = original.prerequisites.clone
      actions = original.instance_eval { @actions }.clone
      lambda do
        original.class.send(:define_task, original.name=>prerequisites).tap do |task|
          task.comment = original.comment
          actions.each { |action| task.enhance &action }
        end
      end
    end
    @sandbox[:rules] = Rake.application.instance_variable_get(:@rules).clone

    # Create a temporary directory where we can create files, e.g,
    # for projects, compilation. We need a place that does not depend
    # on the current directory.
    @test_dir = File.expand_path('../tmp', File.dirname(__FILE__))
    FileUtils.mkpath @test_dir
    # Move to the work directory and make sure Rake thinks of it as the Rakefile directory.
    @sandbox[:pwd] = Dir.pwd
    Dir.chdir @test_dir
    @sandbox[:load_path] = $LOAD_PATH.clone
    @sandbox[:loaded_features] = $LOADED_FEATURES.clone
    @sandbox[:original_dir] = Rake.application.original_dir 
    Rake.application.instance_eval { @original_dir = Dir.pwd }
    Rake.application.instance_eval { @rakefile = File.expand_path('buildfile') }
    
    # Later on we'll want to lose all the on_define created during the test.
    @sandbox[:on_define] = Project.class_eval { (@on_define || []).dup }
    @sandbox[:layout] = Layout.default.clone

    # Create a local repository we can play with. However, our local repository will be void
    # of some essential artifacts (e.g. JUnit artifacts required by build task), so we create
    # these first (see above) and keep them across test cases.
    @sandbox[:artifacts] = Artifact.class_eval { @artifacts }.clone
    Buildr.repositories.local = File.join(@test_dir, 'repository')

    @sandbox[:env_keys] = ENV.keys
    ['DEBUG', 'TEST', 'HTTP_PROXY', 'USER'].each { |k| ENV.delete(k) ; ENV.delete(k.downcase) }

    # Don't output crap to the console.
    trace false
    verbose false
  end

  # Call this from teardown.
  def reset
    # Remove testing local repository, and reset all repository settings.
    Buildr.repositories.local = nil
    Buildr.repositories.remote = nil
    Buildr.repositories.release_to = nil
    Buildr.options.proxy.http = nil
    Buildr.instance_eval { @profiles = nil }

    # Get rid of all the projects and the on_define blocks we used.
    Project.clear
    on_define = @sandbox[:on_define]
    Project.class_eval { @on_define = on_define }
    Layout.default = @sandbox[:layout].clone

    # Switch back Rake directory.
    Dir.chdir @sandbox[:pwd]
    original_dir = @sandbox[:original_dir]
    $LOAD_PATH.replace @sandbox[:load_path]
    $LOADED_FEATURES.replace @sandbox[:loaded_features]
    Rake.application.instance_eval { @original_dir = original_dir }
    FileUtils.rm_rf @test_dir

    # Get rid of all the tasks and restore the default tasks.
    Rake::Task.clear
    @sandbox[:tasks].each { |block| block.call }
    Rake.application.instance_variable_set :@rules, @sandbox[:rules]

    # Get rid of all artifacts and addons.
    @sandbox[:artifacts].tap { |artifacts| Artifact.class_eval { @artifacts = artifacts } }
    Addon.instance_eval { @addons.clear }

    # Restore options.
    Buildr.options.test = nil
    (ENV.keys - @sandbox[:env_keys]).each { |key| ENV.delete key }
  end

end
