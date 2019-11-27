#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

snap_install "code" "--classic"

func_print_info_message "script end `basename "$0"`"

