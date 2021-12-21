#!/bin/bash

if [ `id -u` != "0" ]; then
    echo "EXIT[ERR]: need to run as root, exiting"
    exit -1
fi

source ./common_bash_funcs.sh

wget https://repo.skype.com/latest/skypeforlinux-64.deb
sudo dpkg -i skypeforlinux-64.deb
rm -f skypeforlinux-64.deb

func_print_info_message "script end `basename "$0"`"
