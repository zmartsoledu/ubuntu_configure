#!/bin/sh

if [ `id -u` != "0" ]; then
    echo "EXIT[ERR]: need to run as root, exiting"
    exit -1
fi

grep 'dns=default' /etc/NetworkManager/NetworkManager.conf >/dev/null 2>&1
if [ $? -ne 0 ];
	sed -i '/\[main\]/a dns=default' /etc/NetworkManager/NetworkManager.conf
fi

systemctl disable --now systemd-resolved && \
rm /etc/resolv.conf && \
systemctl restart NetworkManager
