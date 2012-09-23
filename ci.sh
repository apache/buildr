#!/usr/bin/env bash

export JAVA_HOME=/home/hudson/tools/java/latest1.6-64 ;
export SCALA_HOME=/home/hudson/tools/scala-2.9.0.1 ;

source .rvmrc

if [ "X$JOB_NAME" == "XBuildr-ci-build" ]; then
  rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake ci --trace 2>&1
fi

