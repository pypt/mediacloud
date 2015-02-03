#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

set -e
set -o  errexit

# Apparently Perlbrew's scripts contain a lot of uninitialized variables
set +u

if [ `getconf LONG_BIT` != '64' ]; then
    echo "Install failed, you must have a 64 bit OS."
    exit 1
fi

echo "Installing Perlbrew..."
curl -LsS http://install.perlbrew.pl | bash

echo "Loading Perlbrew environment variables..."
source ~/perl5/perlbrew/etc/bashrc

echo "Running 'perlbrew init'..."
perlbrew init

echo "Running 'perlbrew install'..."
nice perlbrew install perl-5.16.3 -Duseithreads -Dusemultiplicity -Duse64bitint -Duse64bitall -Duseposix -Dusethreads -Duselargefiles -Dccflags=-DDEBIAN

echo "Switching to installed Perl..."
perlbrew switch perl-5.16.3

echo "Installing cpanm..."
perlbrew install-cpanm

echo "Creating 'mediacloud' library..."
perlbrew lib create mediacloud

echo "Switching to 'mediacloud' library..."
perlbrew switch perl-5.16.3@mediacloud

echo "Done installing Perl with Perlbrew."

# Set back to "fail on unitialized variables"
set -u
