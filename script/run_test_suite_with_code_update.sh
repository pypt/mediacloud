#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

cd ..

git pull
./script/run_test_suite.sh 
