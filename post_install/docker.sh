#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

apt_update

if [[ 1 == 1 ]]; then
	echo "attempting to remove old docker packages"
	sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge docker* runc >/dev/null 2>&1
	sudo rm -rf /etc/apt/sources.list.d/docker*
fi

sudo systemctl status docker --no-pager

if [[ 1 == 1 ]]; then
	apt_update
	apt_group_install_auto_yes "docker.io docker-compose"
	sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y
else
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

	sudo apt-key fingerprint 0EBFCD88

	sudo systemctl status docker --no-pager
	curl -fsSL https://get.docker.com -o get-docker.sh
	sudo sh get-docker.sh
	rm -rf get-docker.sh

	apt_update
	apt_group_install_auto_yes "docker-ce docker-ce-cli containerd.io docker-compose"
	sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y
fi

sudo groupadd docker
sudo usermod -aG docker `getent group sudo | awk -F: '{print $4}'`
sudo systemctl start docker
sudo systemctl status docker --no-pager

docker run hello-world

func_print_info_message "script end `basename "$0"`"
exit 0
