#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends software-properties-common apt-transport-https ca-certificates wget || true
add-apt-repository -y universe || true
apt-get update -y
apt --fix-broken install -y || true
apt-get install -y --no-install-recommends fonts-liberation lsb-release || true

cd /tmp
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
# install and let apt fix missing deps if dpkg leaves them unmet
dpkg -i google-chrome-stable_current_amd64.deb || true
apt-get install -f -y || true
apt --fix-broken install -y || true
rm -f google-chrome-stable_current_amd64.deb
cd -

func_print_info_message "script end `basename "$0"`"
