#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh


netplan_used=0
which netplan > /dev/null
if [ $? -eq 0 ]; then
	netplan_used=1
	grep 'NetworkManager' /etc/netplan/00-installer-config.yaml > /dev/null
	if [ $? -eq 1 ]; then
		echo "  renderer: NetworkManager" >> /etc/netplan/00-installer-config.yaml
		# also add optional: true to each network interface
	fi
fi

apt_update
apt_group_install_auto_yes "gddrescue \
	gconf2 \
	gigolo \
	gnuplot \
	gparted \
	gitk \
	debconf-utils \
	meld \
	filezilla \
	putty \
	galculator \
	diodon \
	cutecom \
	graphviz \
	synaptic \
	cmake \
	cmake-format \
	qtbase5-dev \
	qtchooser \
	qt5-qmake \
	qtbase5-dev-tools \
	qtcreator \
	pidgin \
	openjdk-11-jdk \
	sqlite3 \
	sqlitebrowser \
	openconnect \
	network-manager \
	network-manager-openconnect \
	network-manager-openconnect-gnome"

apt_group_install_auto_yes "gcc-12"

snap_group_install "multipass"
#snap_group_install "eclipse" "--classic"

snap_group_install "postman"
snap_group_install "drawio"

./solarize.sh
./wireshark.sh
./anaconda.sh
#./arduino.sh
./visual_studio_code.sh
#./skype.sh
./sensors.sh
./mic_noise_cancelling.sh
./nm_dns.sh

if ! grep -q "$(hostname)" /etc/hosts; then
    sudo sed -i "1i\127.0.0.1 $(hostname)" /etc/hosts
fi

if [ $netplan_used -eq 1 ]; then
	rm -rf /etc/resolv.conf
	mkdir -p /run/resolvconf/
	touch /run/resolvconf/resolv.conf
	
	# temporary addition until the system sorts itself out
	echo "nameserver 8.8.8.8" > /run/resolvconf/resolv.conf
	ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
	netplan apply
	systemctl restart NetworkManager
	
	apt_group_install_auto_yes "resolvconf"
	sudo sed -i 's/#FallbackDNS=.*/FallbackDNS=8.8.8.8 8.8.4.4/' /etc/systemd/resolved.conf
	
	netplan apply
	systemctl restart NetworkManager
fi

opt_selection="";
while [ "$opt_selection" != "y" ] && [ "$opt_selection" != "n" ]; do
	read -t 10 -p "Do you want to proceed to installing optional packages [y/N]: " opt_selection;
	opt_selection=${opt_selection,,};
	if [ -z "$opt_selection" ]; then
		opt_selection="y"
	fi
done

func_print_info_message "script end `basename "$0"`"

if [ "${opt_selection}" == "y" ]; then
	echo "proceeding with the optionals"
	./4_graph_optionals.sh
else
	echo "skipping installing the optionals"
fi

exit 0
