update_bundler() {
  gem list | grep 'bundler' &> /dev/null
  if [ $? -gt 0 ]; then
    gem install bundler
  fi
  if [ "$1" = 'quiet' ]; then
    bundle install --deployment > /dev/null 2> /dev/null
  else
    bundle install --deployment
  fi
}

i="0"

until (bundle check > /dev/null 2> /dev/null) || [ $i -gt 10 ]; do
  echo "Bundle update. Attempt: $i"
  update_bundler 'quiet'
  i=$[$i+1]
done

if !(bundle check > /dev/null 2> /dev/null); then
  echo "Last Bundle update attempt."
  update_bundler
fi
