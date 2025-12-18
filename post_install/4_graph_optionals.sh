#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

echo -e "\nupdate and install main apt packages\n"
apt_upgrade

# Install from apt - NO SNAPS
apt_group_install_auto_yes "gimp \
firefox \
ghex \
vlc \
simplescreenrecorder \
libdvdnav4 \
gstreamer1.0-plugins-bad \
gstreamer1.0-plugins-ugly \
libdvd-pkg \
ubuntu-restricted-extras \
network-manager-openconnect-gnome \
pavucontrol \
libcanberra-gtk-module \
clamav \
clamav-daemon \
clamtk \
safeeyes \
apt-transport-tor"

# Firefox from Mozilla PPA (to avoid snap)
func_print_info_message "Setting up Firefox from Mozilla PPA..."
add-apt-repository -y ppa:mozillateam/ppa
cat > /etc/apt/preferences.d/mozilla-firefox << 'EOF'
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001

Package: firefox
Pin: version 1:1snap1-0ubuntu2
Pin-Priority: -1
EOF
apt_update
apt_install_auto_yes firefox

# Tor browser (optional)
if false; then
	add_ppa micahflee/ppa
	sudo apt update
	apt_group_install_auto_yes "tor torbrowser-launcher"
	echo "torbrowser-launcher --settings" >> run_manually.sh
else
	echo -e "skipping tor browser installation\n"
fi

# Flatpak apps (snap replacements)
func_print_info_message "Installing flatpak optional apps..."
flatpak install -y flathub org.shotcut.Shotcut 2>/dev/null || func_print_warn_message "Shotcut flatpak failed"
flatpak install -y flathub com.github.IsmaelMartinez.teams_for_linux 2>/dev/null || func_print_warn_message "Teams flatpak failed"

# Microsoft Azure Storage Explorer via snap alternative
# Install from .deb if available
AZURE_STORAGE_DEB_URL="https://go.microsoft.com/fwlink/?LinkId=722418"
wget -O azure-storage-explorer.deb "$AZURE_STORAGE_DEB_URL" 2>/dev/null && {
	apt_install_auto_yes ./azure-storage-explorer.deb
	rm -f azure-storage-explorer.deb
	func_print_ok_message "Azure Storage Explorer installed from deb"
} || func_print_warn_message "Azure Storage Explorer download failed"

SCRIPT_LOC=`pwd`
cd /home/$SUDO_USER

# Pylote
PYLOTE_TAR_FILE="pylote.tar.gz"
wget http://pascal.peter.free.fr/wikiuploads/$PYLOTE_TAR_FILE 2>/dev/null
if [ -f "$PYLOTE_TAR_FILE" ]; then
	tar xzf pylote.tar.gz
	chmod 755 pylote*
	chown $SUDO_USER:$SUDO_USER pylote* -R
	rm -f $PYLOTE_TAR_FILE
fi

# MS Core Fonts
apt purge -y ttf-mscorefonts-installer 2>/dev/null
TTF_DEB_FILE="ttf-mscorefonts-installer_3.8.1_all.deb"
wget http://ftp.de.debian.org/debian/pool/contrib/m/msttcorefonts/$TTF_DEB_FILE 2>/dev/null
if [ -f "$TTF_DEB_FILE" ]; then
	apt_group_install_auto_yes "$PWD/$TTF_DEB_FILE"
	rm -f $TTF_DEB_FILE
fi

apt autoremove -y

cd $SCRIPT_LOC
chown $SUDO_USER run_manually.sh 2>/dev/null
chmod 777 run_manually.sh 2>/dev/null

dpkg-reconfigure libdvd-pkg

echo -e "\n\n"
grep " fail:" install.log 2>/dev/null
if [ "$?" == "0" ]; then
    echo -e "above are the failed packages. if you do not need them, you can simply ignore. otherwise, you'll have to resolve those manually\n\n"
fi

func_print_info_message "script end `basename "$0"`"

echo "all the steps have been completed. now, please execute run_manually.sh in a new shell, ideally after a restart."
