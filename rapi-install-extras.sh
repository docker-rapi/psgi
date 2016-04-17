#!/bin/bash

## rapi-install-extras.sh

# This script maintains the list of defined "extra" packages associated
# with this rapi/psgi image/version. These are common packages that
# are useful for development, etc, but aren't worth baking in to the
# official image/release. This script is designed to be called from either
# a Dockerfile (which derives from rapi/psgi) or later on within a running
# container.
#

if [ ! $RAPI_PSGI_DOCKERIZED ]; then
  echo "This script only runs via the rapi/psgi docker image"
  exit 1
fi

run_func()
{

local touch_file='/.rapi-extras-installed.flag';
if [ -e $touch_file ]; then
  echo -e "rapi/psgi extras already installed\n"
  echo -e " to force reinstall, run: rm $touch_file && $0\n"
  exit
fi

echo -e "\nInstalling rapi/psgi:$RAPI_PSGI_IMAGE_VERSION 'extras' ...\n"

# This command is structured the same as if it were a Dockerfile RUN
# command to keep the image size/layers as small as possible:

apt-get update && apt-get install -y \
  net-tools \
  dnsutils \
  nmap \
  tcpdump \
&& rm -fr /var/lib/apt/lists/* \
&& touch $touch_file

}
run_func
