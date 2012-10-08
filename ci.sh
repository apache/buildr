#!/usr/bin/env bash

export SCALA_HOME=/home/hudson/tools/scala-2.9.0.1 ;

# Default the rake task to ci if not otherwise overwritten
export BUILD_RAKE_TASK=ci

# Override any specific settings for particular jobs
if [ "X$JOB_NAME" == "XBuildr-metrics-build" ]; then
  export BUILD_RVM=1.9.2
  export BUILD_RAKE_TASK="coverage metrics:saikuro"
  export BUILDR_GEMSET=$JOB_NAME
elif [ "X$JOB_NAME" == "XBuildr-website-build" ]; then
  export BUILD_RVM=1.9.3
  export BUILD_JVM=1.7
  export BUILD_RAKE_TASK=jekyll
  export PATH=$PATH:/home/toulmean/prince/bin
  export BUILDR_GEMSET=$JOB_NAME
elif [ "X$JOB_NAME" == "XBuildr-omnibus-build" ]; then
  export BUILD_RVM=1.8.7
  export BUILD_RAKE_TASK=all-in-one
  export BUILDR_GEMSET=$JOB_NAME
fi

# Select the JVM and default to 1.7 if not specified
if [ "X$BUILD_JVM" == "X1.5" ]; then
  export JAVA_HOME=/home/hudson/tools/java/latest1.5-64
elif [ "X$BUILD_JVM" == "X1.6" ]; then
  export JAVA_HOME=/home/hudson/tools/java/latest1.6-64
else
  export JAVA_HOME=/home/hudson/tools/java/latest1.7-64
fi

# Select the Ruby virtual machine and default to 1.9.3 if not specified
if [ "X$BUILD_RVM" == "X1.9.2" ]; then
  export BUILDR_RUBY_VERSION=ruby-1.9.2-p320
elif [ "X$BUILD_RVM" == "X1.8.7" ]; then
  export BUILDR_RUBY_VERSION=ruby-1.8.7-p358
elif [ "X$BUILD_RVM" == "Xjruby" ]; then
  export BUILDR_RUBY_VERSION=jruby-1.6.7
else
  export BUILDR_RUBY_VERSION=ruby-1.9.3-p194
fi

export LD_LIBRARY_PATH=/home/hudson/.rvm/usr/lib
source "$HOME/.rvm/scripts/rvm"

rvm ${BUILDR_RUBY_VERSION} --force gemset delete ${BUILDR_GEMSET} 2>&1 > /dev/null

source .rvmrc

rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake $BUILD_RAKE_TASK --trace 2>&1
