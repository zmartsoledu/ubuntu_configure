#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

vagrant_url="https://www.vagrantup.com/downloads.html"
vagrant_dir="vagrant_dl"

mkdir -p $vagrant_dir && cd $vagrant_dir
rm -rf *

apt_add "https://apt.releases.hashicorp.com"

apt_group_install_auto_yes "vagrant"

vagrant --version

cd ..
rm -rf $vagrant_dir

func_print_info_message "script end `basename "$0"`"
exit 0
