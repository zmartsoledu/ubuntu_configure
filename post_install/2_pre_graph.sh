#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

./graphics_card.sh
./gnome_desktop.sh
./chrome.sh

if [ -f "run_manually.sh" ]; then
	chmod 755 run_manually.sh
	./run_manually.sh
fi

func_print_info_message "script end `basename "$0"`"

echo "pre-graph steps are completed. restarting your pc and then you can continue with the post-graph setup"
sleep 3
# let's enforce a reboot until the nvidia graphics driver console log spamming issue is resolved
sync && reboot -f

exit 0
