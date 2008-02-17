#!/bin/sh
version=$(ruby --version)
if [ ${version:5:5} \< '1.8.6' ] ; then
  echo "You do not have Ruby 1.8.6 or later, attempting to install a newer version."
  if [ `which port` ] ; then
    echo "Installing Ruby using MacPorts"
    sudo port install ruby rb-rubygems
  elif [ `which fink` ] ; then
    echo "Installing Ruby using Fink"
    sudo fink install ruby ruby18-dev rubygems-rb18
  else
    echo "Can only upgrade to Ruby 1.8.6 using either MacPorts or Fink, and can't find either one"
    exit 1
  fi
  echo
fi

if [ -z $JAVA_HOME ] ; then
  echo "Setting JAVA_HOME"
  export JAVA_HOME=/Library/Java/Home
fi

if [ $(gem --version) \< '1.0.1' ] ; then
  echo "Upgrading to RubyGems 1.0.1"
  sudo gem update --system
  echo
fi

if [ `which buildr` ] ; then
  echo "Updating to the latest version of Buildr"
  sudo env JAVA_HOME=$JAVA_HOME gem update buildr
else
  echo "Installing the latest version of Buildr"
  sudo env JAVA_HOME=$JAVA_HOME gem install buildr
fi
echo

buildr --version
