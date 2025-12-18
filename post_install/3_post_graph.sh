#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

# Switch from netplan to NetworkManager
netplan_used=0
which netplan > /dev/null
if [ $? -eq 0 ]; then
	netplan_used=1
	
	# Check if already configured for NetworkManager
	if [ -f /etc/netplan/01-network-manager-all.yaml ]; then
		func_print_info_message "NetworkManager already configured in netplan"
	else
		# Create NetworkManager netplan config
		cat > /etc/netplan/01-network-manager-all.yaml << 'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
		# Disable old installer config
		if [ -f /etc/netplan/00-installer-config.yaml ]; then
			mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.disabled
		fi
		
		func_print_ok_message "Configured NetworkManager in netplan"
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

# Install flatpak for snap replacements
apt_install_auto_yes "flatpak gnome-software-plugin-flatpak"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install flatpak alternatives to snaps
func_print_info_message "Installing flatpak applications..."
flatpak install -y flathub com.getpostman.Postman 2>/dev/null || func_print_warn_message "Postman install failed or skipped"
flatpak install -y flathub com.jgraph.drawio.desktop 2>/dev/null || func_print_warn_message "Draw.io install failed or skipped"
flatpak install -y flathub com.discordapp.Discord 2>/dev/null || func_print_warn_message "Discord install failed or skipped"
flatpak install -y flathub com.slack.Slack 2>/dev/null || func_print_warn_message "Slack install failed or skipped"
flatpak install -y flathub org.telegram.desktop 2>/dev/null || func_print_warn_message "Telegram install failed or skipped"

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
	
	netplan apply
	systemctl restart NetworkManager
	
	apt_group_install_auto_yes "resolvconf"
	sudo sed -i 's/#FallbackDNS=.*/FallbackDNS=8.8.8.8 8.8.4.4/' /etc/systemd/resolved.conf
	
	netplan apply
	systemctl restart NetworkManager
	systemctl restart systemd-resolved
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
