#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

apt_update
apt_group_install_auto_yes "lm-sensors psensor"

echo "sudo sensors-detect --auto" >> run_manually.sh

func_print_info_message "script end `basename "$0"`"

