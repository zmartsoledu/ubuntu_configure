#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

apt_update
apt_group_install_auto_yes "gddrescue \
	gconf2 \
	gigolo \
	gnuplot \
	virtualbox-qt \
	gparted \
	network-manager \
	gitk tortoisehg \
	debconf-utils \
	meld \
	vim-gnome \
	galculator \
	clipit \
	cutecom \
	graphviz \
	synaptic \
	d-feet"

./solarize.sh
./wireshark.sh
./anaconda.sh
./arduino.sh
./visual_studio_code.sh
./skype.sh
./sensors.sh
./mic_noise_cancelling.sh

opt_selection="";
while [ "$opt_selection" != "y" ] && [ "$opt_selection" != "n" ]; do
	read -t 10 -p "Do you want to proceed to installing optional packages [Y/n]: " opt_selection;
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
