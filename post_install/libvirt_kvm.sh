#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

apt_group_install_auto_yes "qemu-kvm bridge-utils libvirt-dev virtinst virt-top libguestfs-tools libosinfo-bin"
apt_group_install_auto_yes "libvirt-daemon-system libvirt-clients"
apt_group_install_auto_yes "bridge-utils"

sudo adduser `id -un` libvirt >/dev/null 2>&1
sudo adduser `id -un` libvirtd >/dev/null 2>&1

sudo modprobe vhost_net
sudo lsmod | grep vhost
sudo sed -i '/vhost_net/d' /etc/modules
echo "vhost_net" | sudo tee -a /etc/modules

func_print_info_message "script end `basename "$0"`"
exit 0
