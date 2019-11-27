#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

# devices like /dev/ttyUSB etc
usermod -aG tty,dialout $USER

func_print_info_message "script end `basename "$0"`"
