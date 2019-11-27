#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

sudo apt --fix-broken install
apt_install_auto_yes "ubuntu-gnome-desktop" "--reinstall"
sudo apt --fix-broken install

echo "current display manager: "
func_print_info_message "current display manager: `cat /etc/X11/default-display-manager`"

func_print_info_message "script end `basename "$0"`"
