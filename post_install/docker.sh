#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

apt_update

# Remove any old docker installations
echo "attempting to remove old docker packages"
sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge docker docker-engine docker.io containerd runc >/dev/null 2>&1
sudo rm -rf /etc/apt/sources.list.d/docker*

sudo systemctl status docker --no-pager 2>/dev/null

# Install from Ubuntu repos (24.04 has recent docker)
apt_update
apt_group_install_auto_yes "docker.io docker-compose-plugin docker-buildx-plugin"
sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y

# Add all sudo users to docker group
sudo groupadd docker 2>/dev/null
sudo gpasswd -M `getent group sudo | awk -F: '{print $4}'` docker
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl status docker --no-pager

# Test docker
docker run --rm hello-world

func_print_ok_message "docker installed and tested"
func_print_info_message "script end `basename "$0"`"
exit 0
