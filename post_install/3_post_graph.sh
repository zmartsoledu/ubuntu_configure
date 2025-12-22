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

install_postman() {
	local tmpdir
	tmpdir=$(mktemp -d)
	if curl -fsSL https://dl.pstmn.io/download/latest/linux64 -o "$tmpdir/postman.tar.gz"; then
		rm -rf /opt/Postman
		mkdir -p /opt
		tar -xzf "$tmpdir/postman.tar.gz" -C /opt
		chmod +x /opt/Postman/Postman
		ln -sf /opt/Postman/Postman /usr/local/bin/postman
		cat > /usr/share/applications/postman.desktop <<'EOF'
[Desktop Entry]
Name=Postman
Comment=API development environment
Exec=/opt/Postman/Postman
Icon=/opt/Postman/app/resources/app/assets/icon.png
Terminal=false
Type=Application
Categories=Development;
EOF
		chmod 644 /usr/share/applications/postman.desktop
		func_print_ok_message "Postman installed under /opt/Postman"
	else
		func_print_fail_message "Failed to download Postman"
	fi
	rm -rf "$tmpdir"
}

install_drawio() {
	local url
	url=$(python3 - <<'PY'
import json
import sys
import urllib.request
try:
	with urllib.request.urlopen("https://api.github.com/repos/jgraph/drawio-desktop/releases/latest", timeout=30) as resp:
		data = json.load(resp)
except Exception as exc:
	print("", end="")
	sys.exit(0)
for asset in data.get("assets", []):
	name = asset.get("name", "")
	if name.endswith("amd64.deb"):
		print(asset.get("browser_download_url", ""))
		sys.exit(0)
PY
	)
	if [ -n "$url" ]; then
		install_deb_from_url "Draw.io" "$url"
	else
		func_print_warn_message "Could not determine Draw.io download URL"
	fi
}

install_discord() {
	install_deb_from_url "Discord" "https://discord.com/api/download?platform=linux&format=deb"
}

install_slack() {
	local keyring=/etc/apt/keyrings/slack.gpg
	local list_file=/etc/apt/sources.list.d/slack.list
	mkdir -p /etc/apt/keyrings
	if [ ! -f "$keyring" ]; then
		curl -fsSL https://packagecloud.io/slacktechnologies/slack/gpgkey | gpg --dearmor | tee "$keyring" >/dev/null
		chmod 644 "$keyring"
	fi
	cat > "$list_file" <<EOF
# Slack desktop client
deb [arch=amd64 signed-by=$keyring] https://packagecloud.io/slacktechnologies/slack/debian/ $(lsb_release -sc) main
EOF
	apt_update
	# If apt_update failed, skip installing slack
	if [ $? -eq 0 ]; then
		apt_install_auto_yes slack-desktop
	else
		func_print_warn_message "Skipping slack installation due to apt update failure"
	fi
}

install_telegram() {
	apt_install_auto_yes telegram-desktop
}

# Switch from netplan to NetworkManager
netplan_used=0
which netplan > /dev/null
if [ $? -eq 0 ]; then
	netplan_used=1
	
	# Check if already configured for NetworkManager
	if [ -f /etc/netplan/01-network-manager-all.yaml ]; then
		func_print_info_message "NetworkManager already configured in netplan"
	else
		# Detect first available ethernet-style interface name
		iface=""
		for try in eno ens enp eth en* p*; do
			candidate=$(ls /sys/class/net 2>/dev/null | grep -E "^$try" | head -n1)
			if [ -n "$candidate" ]; then
				iface="$candidate"
				break
			fi
		done
		if [ -z "$iface" ]; then
			# fallback to first non-loopback interface
			iface=$(ls /sys/class/net 2>/dev/null | grep -v lo | head -n1)
		fi
		if [ -z "$iface" ]; then
			func_print_warn_message "No network interface detected; writing minimal netplan config"
			iface=eth0
		fi
		# Create NetworkManager netplan config from repo template
		if [ -f "$(dirname "$0")/netplan_template.yaml" ]; then
			cp "$(dirname "$0")/netplan_template.yaml" /etc/netplan/01-network-manager-all.yaml
			sed -i "s/__IFACE__/$iface/" /etc/netplan/01-network-manager-all.yaml
		else
			cat > /etc/netplan/01-network-manager-all.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    $iface:
      dhcp4: true
      dhcp6: false
      optional: true
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1, 8.8.4.4]
EOF
		fi
		# Set secure permissions
		chmod 0644 /etc/netplan/01-network-manager-all.yaml || true
		# Disable old installer config (rename with trailing underscore)
		if [ -f /etc/netplan/00-installer-config.yaml ]; then
			mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml_ || true
		fi
		# Install NetworkManager early so netplan apply won't fail
		apt_update
		apt_install_auto_yes "network-manager"
		systemctl enable --now NetworkManager 2>/dev/null || true
		# Make other netplan YAMLs optional by renaming with trailing underscore
		for f in /etc/netplan/*.yaml; do
			if [ "$f" != "/etc/netplan/01-network-manager-all.yaml" ]; then
				mv "$f" "${f}_" || true
			fi
		done
		
		func_print_ok_message "Configured NetworkManager in netplan for interface $iface"
	fi
fi

apt_update

# Core development tools - NO SNAPS
apt_group_install_auto_yes "gddrescue \
	gconf2 \
	gigolo \
	gnuplot \
	gparted \
	gitk \
	debconf-utils \
	meld \
	filezilla \
	putty \
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
	openjdk-17-jdk \
	sqlite3 \
	sqlitebrowser \
	openconnect \
	network-manager \
	network-manager-openconnect \
	network-manager-openconnect-gnome"

# GCC 14 in Ubuntu 24.04
apt_group_install_auto_yes "gcc-14 g++-14"
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100
update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100

func_print_info_message "Installing desktop apps without snap/flatpak..."
install_postman
install_drawio
install_discord
install_slack
install_telegram

# Apps that are back in apt repos for 24.04
apt_group_install_auto_yes "ffmpeg pdftk-java"

# PowerShell from Microsoft repo
if ! which pwsh >/dev/null 2>&1; then
	func_print_info_message "Installing PowerShell from Microsoft..."
	wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
	dpkg -i packages-microsoft-prod.deb
	rm -f packages-microsoft-prod.deb
	apt_update
	apt_install_auto_yes powershell
fi

./solarize.sh
./wireshark.sh
./anaconda.sh
./visual_studio_code.sh
./sensors.sh
./mic_noise_cancelling.sh
./nm_dns.sh

# Ensure hostname is in /etc/hosts
if ! grep -q "$(hostname)" /etc/hosts; then
    sudo sed -i "1i\127.0.0.1 $(hostname)" /etc/hosts
fi

# Apply NetworkManager configuration
if [ $netplan_used -eq 1 ]; then
	rm -rf /etc/resolv.conf
	mkdir -p /run/resolvconf/
	touch /run/resolvconf/resolv.conf
	
	# Temporary DNS until NetworkManager takes over
	echo "nameserver 8.8.8.8" > /run/resolvconf/resolv.conf
	ln -sf /run/resolvconf/resolv.conf /etc/resolv.conf
	
	netplan apply 2>/dev/null || true
	systemctl restart NetworkManager 2>/dev/null || true
	
	apt_group_install_auto_yes "resolvconf"
	sudo sed -i 's/#FallbackDNS=.*/FallbackDNS=8.8.8.8 8.8.4.4/' /etc/systemd/resolved.conf
	
	netplan apply 2>/dev/null || true
	systemctl restart NetworkManager 2>/dev/null || true
	systemctl restart systemd-resolved 2>/dev/null || true
fi

opt_selection="";
while [ "$opt_selection" != "y" ] && [ "$opt_selection" != "n" ]; do
	read -t 10 -p "Do you want to proceed to installing optional packages [y/N]: " opt_selection;
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
