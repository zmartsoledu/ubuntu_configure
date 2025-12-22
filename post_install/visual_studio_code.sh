#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

KEYRING=/etc/apt/keyrings/packages.microsoft.gpg
REPO_FILE=/etc/apt/sources.list.d/vscode.list

# Clean up any conflicting old VS Code repo entries
rm -f /etc/apt/sources.list.d/vscode.list.*
rm -f /usr/share/keyrings/microsoft.gpg

mkdir -p /etc/apt/keyrings
if [ ! -f "$KEYRING" ]; then
	curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee "$KEYRING" >/dev/null
	chmod 644 "$KEYRING"
fi

echo "deb [arch=amd64,arm64,armhf signed-by=$KEYRING] https://packages.microsoft.com/repos/code stable main" > "$REPO_FILE"

apt_update
apt_install_auto_yes code

func_print_info_message "script end `basename "$0"`"

