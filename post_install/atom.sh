#!/bin/bash

if [ `id -u` != "0" ]; then
    echo "EXIT[ERR]: need to run as root, exiting"
    exit -1
fi

source ./common_bash_funcs.sh

export ATOM_VERSION="v1.37.0"
curl -L https://github.com/atom/atom/releases/download/${ATOM_VERSION}/atom-amd64.deb > /tmp/atom.deb
sudo dpkg -i /tmp/atom.deb
rm -f /tmp/atom.deb

func_print_info_message "script end `basename "$0"`"
