#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

cd ../../solr/mediacloud/
exec java -jar start.jar



