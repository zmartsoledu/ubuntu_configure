#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

# point /bin/sh to bash
ln -sf /bin/bash /bin/sh

rm -rf err.log
apt_upgrade

sudo rmmod floppy >/dev/null 2>&1
echo "blacklist vga16fb" | sudo tee /etc/modprobe.d/novga16fb.conf > /dev/null 2>&1
echo "blacklist floppy" | sudo tee /etc/modprobe.d/blacklist-floppy.conf > /dev/null 2>&1
sudo dpkg-reconfigure initramfs-tools

func_print_info_message "script end `basename "$0"`"

echo "rebooting due to apt-get upgrade"
sleep 3
sudo sync && sudo reboot

exit 0
