#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

add_ppa ubuntuhandbook1/avidemux openshot.developers/ppa audio-recorder/ppa
add_to_sources_list "http://archive.canonical.com/" "partner"

echo -e "\nupdate and install main apt packages\n"
apt_upgrade
apt_group_install_auto_yes "synergy
gimp
vlc browser-plugin-vlc
simplescreenrecorder
libdvdnav4
libdvdread4
gstreamer1.0-plugins-bad
gstreamer1.0-plugins-ugly
libdvd-pkg
ubuntu-restricted-extras
adobe-flashplugin
browser-plugin-freshplayer-pepperflash
network-manager-openconnect-gnome
avidemux2.7-qt5
avidemux2.7-plugins-qt5
openshot-qt
pavucontrol
audio-recorder
libcanberra-gtk-module
clamav
clamav-daemon
clamtk
apt-transport-tor"

# if you want to disable tor browser installation, change the 'true' to 'false' in the line below
if true; then
	add_ppa micahflee/ppa
	sudo apt update
	# deb.torproject.org-keyring
	apt_group_install_auto_yes "tor torbrowser-launcher"

	echo "torbrowser-launcher --settings" >> run_manually.sh
else
	echo -e "skipping tor browser installation\n"
fi

snap_group_install "ghex-udt storage-explorer"
sudo snap connect storage-explorer:password-manager-service :password-manager-service

snap_group_install "cool-retro-term shotcut" "--classic"
which shotcut >/dev/null 2>&1
if [ "$?" != "0" ]; then
	add_ppa haraldhv/shotcut
	apt_install_auto_yes shotcut
fi

func_install_latest_deb_from_github "keeweb/keeweb"
#func_install_latest_deb_from_github "meetfranz/franz"

snap_group_install "discord slack telegram-desktop teams"

SCRIPT_LOC=`pwd`
cd /home/$SUDO_USER
PYLOTE_TAR_FILE="pylote.tar.gz"
wget http://pascal.peter.free.fr/wikiuploads/$PYLOTE_TAR_FILE
if [ -f "$PYLOTE_TAR_FILE" ]; then
	tar xzf pylote.tar.gz
	chmod 755 pylote*
	chown $SUDO_USER:$SUDO_USER pylote* -R
	rm -f $PYLOTE_TAR_FILE
fi

apt purge -y ttf-mscorefonts-installer
TTF_DEB_FILE="ttf-mscorefonts-installer_3.7_all.deb"
wget http://ftp.de.debian.org/debian/pool/contrib/m/msttcorefonts/$TTF_DEB_FILE
if [ -f "$TTF_DEB_FILE" ]; then
	apt_group_install_auto_yes "$PWD/$TTF_DEB_FILE"
	rm -f $TTF_DEB_FILE
fi

apt autoremove -y

cd $SCRIPT_LOC
chown $SUDO_USER run_manually.sh
chmod 777 run_manually.sh

dpkg-reconfigure libdvd-pkg

echo -e "\n\n"
grep " fail:" install.log
if [ "$?" == "0" ]; then
    echo -e "above are the failed packages. if you do not need them, you can simply ignore. otherwise, you'll have to resolve those manually\n\n"
fi

func_print_info_message "script end `basename "$0"`"

echo "all the steps have been completed. now, please execute run_manually.sh in a new shell, ideally after a restart."

