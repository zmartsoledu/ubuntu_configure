#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

# point /bin/sh to bash
ln -sf /bin/bash /bin/sh

mod_requires_reboot="0"
read -p "Enter username for new sudoer, leave empty to skip: "  admin_username
if [ `echo $admin_username | wc -m` -gt '4' ]; then
	mod_requires_reboot="1"
	UID_OPT=""
	# if uid 1000 is free, make sure that we use it
	getent passwd 1000 >/dev/null 2>&1
	if [ "$?" != "0" ]; then
		UID_OPT="--uid 1000"
	fi

	adduser $UID_OPT --gecos "" $admin_username
	usermod -aG sudo $admin_username

	echo "created sudoer $admin_username ."
	echo "after reboot, login as $admin_username and run the /home/$admin_username/first_boot.sh script"
	#echo "sudo passwd $admin_username" > /home/$admin_username/first_boot.sh
	echo "sudo userdel -rf $SUDO_USER > /dev/null 2>&1" >> /home/$admin_username/first_boot.sh
	chmod 755 /home/$admin_username/first_boot.sh

	read -n 1 -s -r -p "Press enter to continue..."
	echo ""
else
	admin_username=$SUDO_USER
fi

echo "current hostname: " `hostname`
read -p "Enter new hostname, leave empty to skip: "  hostname_new
if [ `echo $hostname_new | wc -m` -gt '4' ]; then
	mod_requires_reboot="1"
	hostnamectl set-hostname $hostname_new
	echo "new hostname: " `hostname`
fi

read -p "Do you want to change the encryption passphrase?[y/N]: "  enc_psswd
if [ "$enc_psswd" == "y" ] || [ "$enc_psswd" == "Y" ]; then
	mod_requires_reboot="1"
	disk_suffix=`cat /etc/crypttab | grep -Eo "^sd[a-z][0-9]{1,2}" | head -n1`
	disk_path="/dev/""${disk_suffix}"
	if [ -b "$disk_path" ]; then
		sudo cryptsetup luksAddKey "${disk_path}"
		if [ $? -eq '0' ]; then
			echo "ubuntu" | sudo cryptsetup luksRemoveKey "${disk_path}" >/dev/null 2>&1
			if [ "$?" != "0" ]; then
				echo "enter the old encryption passphrase for removal"
				sudo cryptsetup luksRemoveKey "${disk_path}"
			fi
		fi
	fi
fi

sudo ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime

func_print_info_message "script end `basename "$0"`"

if [ "${mod_requires_reboot}" == "1" ]; then
	echo "rebooting due to username/psswd mods..."
	sleep 3
	custom_reboot
fi

exit 0
