#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

sudo killall VBoxHeadless >/dev/null 2>&1
sudo killall VirtualBox >/dev/null 2>&1

distro_codename=$(cat /etc/*-release | grep "CODENAME=" | tail -n1 | sed 's@.*=\(.*\)@\1@')

wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | sudo apt-key add -

add_to_sources_list "http://download.virtualbox.org/virtualbox/debian" "contrib"

apt_update
echo "attempting to remove old virtualbox packages"
sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge "virtualbox*" "virtualbox-*" >/dev/null 2>&1
apt_group_install_auto_yes "linux-headers-generic \
	virtualbox \
	virtualbox-dkms"

# reconfigure virtualbox components
sudo dpkg-reconfigure virtualbox-dkms
sudo dpkg-reconfigure virtualbox
sudo modprobe vboxdrv

echo virtualbox-ext-pack virtualbox-ext-pack/license select true | sudo debconf-set-selections
apt_group_install_auto_yes "virtualbox-ext-pack"

VBoxManage --version

mkdir -p /media/$USER/ExtraStorageEnc/vms
vboxmanage setproperty machinefolder /media/$USER/ExtraStorageEnc/vms

sudo usermod -aG vboxusers $SUDO_USER
echo "sudo usermod -aG vboxusers $USER" >> run_manually.sh

func_print_info_message "script end `basename "$0"`"
exit 0
