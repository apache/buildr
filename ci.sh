#!/usr/bin/env bash

export SCALA_HOME=/home/hudson/tools/scala-2.9.0.1 ;

# Default the rake task to ci if not otherwise overwritten
export BUILD_RAKE_TASK=ci

# Override any specific settings for particular jobs
if [ "X$BUILD_JOB" == "XBuildr-metrics-build" ]; then
  export BUILD_RVM=1.9.2
  export BUILD_RAKE_TASK="coverage metrics"
elif [ "X$BUILD_JOB" == "XBuildr-website-build" ]; then
  export BUILD_RVM=1.8.7
  export BUILD_JVM=1.6
  export BUILD_RAKE_TASK=jekyll
  export PATH=$PATH:/home/toulmean/prince/bin
elif [ "X$BUILD_JOB" == "XBuildr-omnibus-build" ]; then
  export BUILD_RAKE_TASK=all-in-one
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-1.9" ]; then
  export BUILD_RVM=1.9.2
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-1.9.3" ]; then
  export BUILD_RVM=1.9.3
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-1.8" ]; then
  export BUILD_RVM=1.8.7
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-jruby-jdk1.5" ]; then
  export BUILD_RVM=jruby
  export BUILD_JVM=1.5
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-jruby-jdk1.6" ]; then
  export BUILD_RVM=jruby
  export BUILD_JVM=1.6
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-jruby-jdk1.7" ]; then
  export BUILD_RVM=jruby
  export BUILD_JVM=1.7
fi

# Select the JVM and default to 1.7 if not specified
if [ "X$BUILD_JVM" == "X1.5" ]; then
  export JAVA_HOME=/home/hudson/tools/java/latest1.5-64;
elif [ "X$BUILD_JVM" == "X1.6" ]; then
  export JAVA_HOME=/home/hudson/tools/java/latest1.6-64 ;
else
  export JAVA_HOME=/home/hudson/tools/java/latest1.7-64 ;
end

# Select the Ruby virtual machine and default to 1.9.3 if not specified
if [ "X$BUILD_RVM" == "X1.9.2" ]; then
  export BUILDR_RUBY_VERSION=ruby-1.9.2-p320
elif [ "X$BUILD_JVM" == "X1.8.7" ]; then
  export BUILDR_RUBY_VERSION=ruby-1.8.7-p358
elif [ "X$BUILD_JVM" == "Xjruby" ]; then
  export BUILDR_RUBY_VERSION=jruby-1.6.7
else
  export BUILDR_RUBY_VERSION=ruby-1.9.3-p0
end

export BUILDR_GEMSET=$JOB_NAME

rvm ${BUILDR_RUBY_VERSION} --force gemset delete ${BUILDR_GEMSET} 2>&1 > /dev/null

source .rvmrc

rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake $BUILD_RAKE_TASK --trace 2>&1
