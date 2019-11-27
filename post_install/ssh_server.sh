#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

apt_update
apt_install_auto_yes openssh-server

#grep "PasswordAuth" /etc/ssh/sshd_config
#sudo service ssh restart

func_print_info_message "script end `basename "$0"`"
