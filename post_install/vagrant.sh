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
wget $vagrant_url
host_arch=`uname -i`
vagrant_deb=`grep "${host_arch}.deb" downloads.html | sed 's/.*="\(.*\)".*/\1/'`
wget ${vagrant_deb}

sudo dpkg -i *.deb
sudo apt-get install -f

vagrant --version

cd ..
rm -rf $vagrant_dir

func_print_info_message "script end `basename "$0"`"
exit 0
