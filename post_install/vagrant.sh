#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

vagrant_url="https://www.vagrantup.com/downloads.html"
vagrant_dir="vagrant_dl"

mkdir -p $vagrant_dir && cd $vagrant_dir
rm -rf *

# Clean up legacy apt-key entries for hashicorp from /etc/apt/trusted.gpg
if [ -f /etc/apt/trusted.gpg ]; then
    for keyid in $(apt-key --keyring /etc/apt/trusted.gpg list 2>/dev/null | grep -B1 -i "hashicorp" | grep -oE '[A-F0-9]{8,}' || true); do
        [ -n "$keyid" ] && apt-key --keyring /etc/apt/trusted.gpg del "$keyid" 2>/dev/null || true
    done
fi

# Remove any conflicting legacy source files for hashicorp
for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    if grep -q "hashicorp" "$f" 2>/dev/null; then
        if ! grep -q "signed-by=/etc/apt/keyrings/apt.releases.hashicorp.com.gpg" "$f" 2>/dev/null; then
            func_print_info_message "Removing conflicting legacy source: $f"
            rm -f "$f"
        fi
    fi
done

# Remove hashicorp entries from main sources.list if present
if grep -q "hashicorp" /etc/apt/sources.list 2>/dev/null; then
    func_print_info_message "Removing hashicorp entries from /etc/apt/sources.list"
    sed -i "/hashicorp/d" /etc/apt/sources.list 2>/dev/null || true
fi

apt_add "https://apt.releases.hashicorp.com"

apt_group_install_auto_yes "vagrant"

vagrant --version

cd ..
rm -rf $vagrant_dir

func_print_info_message "script end `basename "$0"`"
exit 0
