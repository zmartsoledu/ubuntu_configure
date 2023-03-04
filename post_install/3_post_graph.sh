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

snap_group_install "multipass"

./solarize.sh
./wireshark.sh
./anaconda.sh
#./arduino.sh
./visual_studio_code.sh
#./skype.sh
./sensors.sh
./mic_noise_cancelling.sh
./nm_dns.sh

opt_selection="";
while [ "$opt_selection" != "y" ] && [ "$opt_selection" != "n" ]; do
	read -t 10 -p "Do you want to proceed to installing optional packages [y/N]: " opt_selection;
	opt_selection=${opt_selection,,};
	if [ -z "$opt_selection" ]; then
		opt_selection="y"
	fi
done

if [ $netplan_used -eq 1 ]; then
	netplan apply
	rm -rf /etc/resolv.conf
	ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
fi

func_print_info_message "script end `basename "$0"`"

if [ "${opt_selection}" == "y" ]; then
	echo "proceeding with the optionals"
	./4_graph_optionals.sh
else
	echo "skipping installing the optionals"
fi

exit 0
