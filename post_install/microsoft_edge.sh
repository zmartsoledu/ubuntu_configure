#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

KEYRING=/etc/apt/keyrings/microsoft-edge.gpg
REPO_FILE=/etc/apt/sources.list.d/microsoft-edge.list

mkdir -p /etc/apt/keyrings
if [ ! -f "$KEYRING" ]; then
	curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee "$KEYRING" >/dev/null
	chmod 644 "$KEYRING"
fi

# Add Edge repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING] https://packages.microsoft.com/repos/edge stable main" > "$REPO_FILE"

apt_update
apt_install_auto_yes microsoft-edge-stable || func_print_warn_message "Failed to install Microsoft Edge"

func_print_info_message "script end `basename \"$0\"`"
