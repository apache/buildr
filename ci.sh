#!/usr/bin/env bash

export SCALA_HOME=/home/hudson/tools/scala-2.9.0.1 ;
export BUILD_TASK=$JOB_NAME

if [ "X$BUILD_TASK" == "XBuildr-ci-build" ]; then
  export JAVA_HOME=/home/hudson/tools/java/latest1.6-64 ;
  source .rvmrc
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake ci --trace 2>&1
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-1.9" ]; then
  export JAVA_HOME=/home/hudson/tools/java/latest1.6-64 ;
  export BUILDR_RUBY_VERSION=ruby-1.9.2-p320
  source .rvmrc
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake ci --trace 2>&1
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-1.8" ]; then
  export JAVA_HOME=/home/hudson/tools/java/latest1.6-64 ;
  export BUILDR_RUBY_VERSION=ruby-1.8.7-p358
  source .rvmrc
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake ci --trace 2>&1
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-jruby-jdk1.5" ]; then
  export BUILDR_RUBY_VERSION=jruby-1.6.7
  export JAVA_HOME=/home/hudson/tools/java/latest1.5-64 ;
  source .rvmrc
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake ci --trace 2>&1
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-jruby-jdk1.6" ]; then
  export BUILDR_RUBY_VERSION=jruby-1.6.7
  export JAVA_HOME=/home/hudson/tools/java/latest1.6-64 ;
  source .rvmrc
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake ci --trace 2>&1
elif [ "X$BUILD_TASK" == "XBuildr-ci-build-jruby-jdk1.7" ]; then
  export BUILDR_RUBY_VERSION=jruby-1.6.7
  export JAVA_HOME=/home/hudson/tools/java/latest1.7-64 ;
  source .rvmrc
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake ci --trace 2>&1
elif [ "X$BUILD_TASK" == "XBuildr-metrics-build" ]; then
  export BUILDR_RUBY_VERSION=ruby-1.9.2-p320
  export JAVA_HOME=/home/hudson/tools/java/latest1.6-64 ;
  source .rvmrc
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake coverage metrics --trace 2>&1
elif [ "X$BUILD_TASK" == "XBuildr-website-build" ]; then
  export BUILDR_RUBY_VERSION=ruby-1.8.7-p358
  export JAVA_HOME=/home/hudson/tools/java/latest1.6-64 ;
  export PATH=$PATH:/home/toulmean/prince/bin
  source .rvmrc
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake jekyll --trace 2>&1
elif [ "X$BUILD_TASK" == "XBuildr-omnibus-build" ]; then
  export BUILDR_RUBY_VERSION=ruby-1.9.2-p320
  export JAVA_HOME=/home/hudson/tools/java/latest1.7-64 ;
  source .rvmrc
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake all-in-one --trace 2>&1
else
  echo "Unknown build job"
  exit 42
fi
