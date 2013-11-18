#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

if pwd | grep ' ' ; then
    echo "Media Cloud cannot be installed in a file path with spaces in its name"
    exit 1
fi

# Gearman::XS, the dependency of Gearman::JobScheduler, depends on
# Module::Install, but the author of the module (probably) forgot to add it so
# the list of dependencies (https://rt.cpan.org/Ticket/Display.html?id=89690),
# so installing it separately
mkdir -p local/
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ Module::Install

# Graph::Layout::Aesthetic doesn't compile on newer compilers, so install a
# monkey-patched version of the module beforehand
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ git://github.com/pypt/p5-Graph-Layout-Aesthetic.git@0.12

# Install the rest of the modules
source ./script/set_java_home.sh
JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install --deployment

echo "Successfully installed Perl and modules for MediaCloud"
