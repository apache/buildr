#!/bin/sh
if [ -z `which ruby` ] ; then
  echo "You do not have Ruby 1.8.6 ..."
  if [ `which yum` ] ; then
    echo "Installing Ruby using yum"
    sudo yum install ruby rubygems 
  elif [ `which apt-get` ] ; then
    echo "Installing Ruby using apt-get"
    # ruby package does not contain RDoc, IRB, etc; ruby-full is a meta-package.
    # build-essentials not installed by default in Ubuntu, required for C extensions.
    sudo apt-get install ruby-full ruby1.8-dev build-essential libopenssl-ruby
    # RubyGems broken on Ubunutu, installing directly from source.
    echo "Installing RubyGems from RubyForge"
    curl -OL http://rubyforge.org/frs/download.php/29548/rubygems-1.0.1.tgz
    tar xzf rubygems-1.0.1.tgz
    cd rubygems-1.0.1
    sudo ruby setup.rb
    cd ..
    rm -rf rubygems-1.0.1
    # ruby is same as ruby1.8, we need gem that is same as gem1.8
    sudo ln -s /usr/bin/gem1.8 /usr/bin/gem
  else
    echo "Can only install Ruby 1.8.6 using either yum or apt-get, and can't find either one"
    exit 1
  fi
  echo
fi

if [ -z $JAVA_HOME ] ; then
  echo "Please set JAVA_HOME before proceeding"
  exit 1
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
