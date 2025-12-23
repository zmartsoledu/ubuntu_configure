#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

install_deb_from_url() {
	local name="$1"
	local url="$2"
	local tmp
	tmp=$(mktemp --suffix=.deb)
	if curl -fsSL "$url" -o "$tmp"; then
		if dpkg -i "$tmp" >/dev/null 2>&1; then
			func_print_ok_message "$name installed"
		else
			func_print_warn_message "Resolving dependencies for $name"
			DEBIAN_FRONTEND=noninteractive apt-get install -f -y >/dev/null 2>&1 || true
			if dpkg -i "$tmp" >/dev/null 2>&1; then
				func_print_ok_message "$name installed"
			else
				func_print_fail_message "$name installation failed"
			fi
		fi
	else
		func_print_fail_message "Failed to download $name"
	fi
	rm -f "$tmp"
}

install_teams_for_linux() {
	local url
	url=$(python3 - <<'PY'
import json
import sys
import urllib.request
try:
	with urllib.request.urlopen("https://api.github.com/repos/IsmaelMartinez/teams-for-linux/releases/latest", timeout=30) as resp:
		data = json.load(resp)
except Exception:
	sys.exit(0)
for asset in data.get("assets", []):
	name = asset.get("name", "")
	if name.endswith("amd64.deb"):
		print(asset.get("browser_download_url", ""))
		sys.exit(0)
PY
	)
	if [ -n "$url" ]; then
		install_deb_from_url "teams-for-linux" "$url"
	else
		func_print_warn_message "Could not locate teams-for-linux release"
	fi
}

install_storage_explorer() {
	local tmpdir
	tmpdir=$(mktemp -d)
	local archive="$tmpdir/storage.tar.gz"
	if curl -fsSL https://go.microsoft.com/fwlink/?LinkId=722418 -o "$archive"; then
		local extract_dir="$tmpdir/extracted"
		mkdir -p "$extract_dir"
		tar -xzf "$archive" -C "$extract_dir"
		local payload
		payload=$(find "$extract_dir" -maxdepth 1 -mindepth 1 -type d | head -n1)
		if [ -z "$payload" ]; then
			func_print_warn_message "Azure Storage Explorer archive format unexpected"
		else
			rm -rf /opt/StorageExplorer
			mkdir -p /opt
			mv "$payload" /opt/StorageExplorer
			chmod +x /opt/StorageExplorer/StorageExplorer 2>/dev/null || true
			ln -sf /opt/StorageExplorer/StorageExplorer /usr/local/bin/storage-explorer
			local icon_path
			icon_path=$(find /opt/StorageExplorer -maxdepth 4 -type f -name '*.png' | head -n1)
			[ -z "$icon_path" ] && icon_path=/opt/StorageExplorer/StorageExplorer
			cat > /usr/share/applications/storage-explorer.desktop <<EOF
[Desktop Entry]
Name=Azure Storage Explorer
Comment=Microsoft Azure Storage Explorer
Exec=/usr/local/bin/storage-explorer
Icon=$icon_path
Terminal=false
Type=Application
Categories=Utility;
EOF
			chmod 644 /usr/share/applications/storage-explorer.desktop
			func_print_ok_message "Azure Storage Explorer installed under /opt/StorageExplorer"
		fi
	else
		func_print_warn_message "Azure Storage Explorer download failed"
	fi
	rm -rf "$tmpdir"
}

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
gnome-shell-extension-manager \
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
# Also install Microsoft Edge
./microsoft_edge.sh || func_print_warn_message "Microsoft Edge installation failed"

# Tor browser (optional)
if false; then
	add_ppa micahflee/ppa
	sudo apt update
	apt_group_install_auto_yes "tor torbrowser-launcher"
	echo "torbrowser-launcher --settings" >> run_manually.sh
else
	echo -e "skipping tor browser installation\n"
fi

func_print_info_message "Installing optional desktop apps without flatpak..."
apt_install_auto_yes shotcut
install_teams_for_linux
install_storage_explorer

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
TTF_DEB_FILE="/tmp/ttf-mscorefonts-installer_3.8.1_all.deb"
rm -f "$TTF_DEB_FILE"
wget -O "$TTF_DEB_FILE" http://ftp.de.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8.1_all.deb 2>/dev/null
if [ -f "$TTF_DEB_FILE" ]; then
	apt_group_install_auto_yes "$TTF_DEB_FILE"
	rm -f "$TTF_DEB_FILE"
fi

apt autoremove -y

# Fix any broken packages before reconfiguring libdvd-pkg
apt-get install -f -y || true

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
