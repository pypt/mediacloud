#!/bin/bash

set -u
set -o errexit

if [ `uname` == 'Darwin' ]; then
    # Mac OS X -- nothing to do
    :
else

    MEDIACLOUD_USER=`id -un`
    echo "Setting required kernel parameters via limits.conf for user '$MEDIACLOUD_USER'..."

    LIMITS_FILE=/etc/security/limits.d/50-mediacloud.conf

    if [ -f "$LIMITS_FILE" ]; then
        echo "Limits file $LIMITS_FILE already exists, please either remove it or add parameters manually."
        exit 1
    fi

    sudo tee "$LIMITS_FILE" <<EOF
#
# Media Cloud limits
#

# Each process is limited up to ~34 GB of memory
$MEDIACLOUD_USER      hard    as            33554432

# Increase the max. open files limit
$MEDIACLOUD_USER      soft    nofile        65536
$MEDIACLOUD_USER      hard    nofile        65536
EOF

    echo "Done setting required kernel parameters via limits.conf."
    echo "Please relogin to the user '$MEDIACLOUD_USER' for the limits to be applied."

fi
