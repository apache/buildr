#!/bin/sh

if [ -z `which jruby` ] ; then
  version=1.1RC2
  target=/opt/jruby
  echo "Installing JRuby ${version} in ${target}"
  sudo mkdir -p $(dirname ${target})
  curl -OL http://dist.codehaus.org/jruby/jruby-bin-${version}.tar.gz
  tar -xz < jruby-bin-${version}.tar.gz
  sudo mv jruby-${version} ${target}
  rm jruby-bin-${version}.tar.gz
  export PATH=$PATH:${target}
  if [ -e ~/.bash_profile ] ; then
    echo "export PATH=${target}/bin:\$PATH" >> ~/.bash_profile
  elif [ -e ~/.profile ] ; then
    echo "export PATH=${target}/bin:\$PATH" >> ~/.profile
  else
    echo "You need to add ${target}/bin to the PATH"
  fi
fi

if [ `which buildr` ] ; then
  echo "Updating to the latest version of Buildr"
  sudo jruby -S gem update buildr
else
  echo "Installing the latest version of Buildr"
  sudo jruby -S gem install buildr
fi
echo

jruby -S buildr --version
