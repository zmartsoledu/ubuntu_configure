#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

wget -q -O - archive.kali.org/archive-key.asc | sudo  apt-key add
apt_update

git clone https://github.com/LionSec/katoolin.git
sudo cp katoolin/katoolin.py /usr/bin/katoolin
sudo chmod +x /usr/bin/katoolin
#sudo katoolin

sudo rm -rf katoolin

func_print_info_message "script end `basename "$0"`"
