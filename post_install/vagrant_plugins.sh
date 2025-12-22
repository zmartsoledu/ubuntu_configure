#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

echo "installing vagrant plugins..."
sudo vagrant plugin install vagrant-libvirt
sudo vagrant plugin install vagrant-vbguest
sudo vagrant plugin install vagrant-disksize
# vagrant-azure is deprecated and has conflicting faraday dependencies; skipped
# sudo vagrant plugin install vagrant-azure

vagrant plugin list

func_print_info_message "script end `basename "$0"`"
exit 0
