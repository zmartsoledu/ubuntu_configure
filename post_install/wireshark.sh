#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

add_ppa wireshark-dev/stable
apt_update
apt_install_auto_yes wireshark

echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure wireshark-common

sudo usermod -aG wireshark $SUDO_USER
echo 'sudo usermod -aG wireshark $USER' >> run_manually.sh

func_print_info_message "script end `basename "$0"`"


