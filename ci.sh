#!/usr/bin/env bash

export SCALA_HOME=/home/hudson/tools/scala-2.9.0.1 ;

# Default the rake task to ci if not otherwise overwritten
export BUILD_RAKE_TASK=ci

# Override any specific settings for particular jobs
if [ "X$JOB_NAME" == "XBuildr-metrics-build" ]; then
  export BUILD_RVM=1.9.2
  export BUILD_RAKE_TASK="coverage metrics"
  export BUILDR_GEMSET=$JOB_NAME
elif [ "X$JOB_NAME" == "XBuildr-website-build" ]; then
  export BUILD_RVM=1.8.7
  export BUILD_JVM=1.6
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

function __sig_exit {
  echo "Cleaing up locks"
  rm -rf mkdir "$HOME/.rvm_lock"
}

function __sig_int {
    echo "WARNING: SIGINT caught"
    exit 1002
}

function __sig_quit {
    echo "SIGQUIT caught"
    exit 1003
}

function __sig_term {
    echo "WARNING: SIGTERM caught"
    exit 1015
}

function __sig_noop {
	true
}

while ! `mkdir "$HOME/.rvm_lock" 2>&1 > /dev/null`; do
  echo "Waiting"
  sleep 1
done

trap __sig_exit EXIT    # SIGEXIT
trap __sig_int INT      # SIGINT
trap __sig_quit QUIT    # SIGQUIT
trap __sig_term TERM    # SIGTERM

export BUILDR_GEMSET=${BUILDR_GEMSET-CI_$BUILD_JVM}
export PATH=$JAVA_HOME/bin:$PATH
export PATH=$PATH:$HOME/.rvm/bin

export EXPECTED_RVM=random_value
export CURRENT_RVM=`cat "$HOME/.rvm_install" 2>&1`
if [ "X$CURRENT_RVM" != "X$EXPECTED_RVM" ]; then
  echo Removing old RVM version
  rm -rf "$HOME/.rvm"
fi

if [[ ! -s "$HOME/.rvm/scripts/rvm" ]]; then
  curl -L https://get.rvm.io | bash -s stable --auto
  echo $EXPECTED_RVM > "$HOME/.rvm_install"
  touch "$HOME/.rvm_ci_update"
else
  if test `find "$HOME/.rvm_ci_update" -mmin +7200 2>&1 > /dev/null`; then
    source "$HOME/.rvm/scripts/rvm"
    rvm get stable --auto
    touch "$HOME/.rvm_ci_update"
  fi
fi

rmdir "$HOME/.rvm_lock"

trap __sig_noop EXIT    # SIGEXIT
trap __sig_noop INT      # SIGINT
trap __sig_noop QUIT    # SIGQUIT
trap __sig_noop TERM    # SIGTERM

source "$HOME/.rvm/scripts/rvm"

rvm ${BUILDR_RUBY_VERSION} --force gemset delete ${BUILDR_GEMSET} 2>&1 > /dev/null

source .rvmrc

rvm "${BUILDR_RUBY_VERSION}@${BUILDR_GEMSET}" exec rake $BUILD_RAKE_TASK --trace 2>&1
