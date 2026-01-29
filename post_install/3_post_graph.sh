#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

# Clean up conflicting Microsoft repo entries ONCE at the start
func_print_info_message "Cleaning up any conflicting Microsoft GPG keys and repo entries..."
rm -f /etc/apt/sources.list.d/vscode.list.* 2>/dev/null
rm -f /usr/share/keyrings/microsoft.gpg 2>/dev/null
# Remove duplicate VS Code sources but keep the one we'll create
find /etc/apt/sources.list.d/ -type f \( -name '*vscode*' -o -name '*code*' \) ! -name 'vscode.list' -delete 2>/dev/null || true
# Remove broken Slack repo

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
	req = urllib.request.Request("https://api.github.com/repos/jgraph/drawio-desktop/releases/latest")
	req.add_header('User-Agent', 'Mozilla/5.0')
	with urllib.request.urlopen(req, timeout=30) as resp:
		data = json.load(resp)
		for asset in data.get("assets", []):
			name = asset.get("name", "")
			if name.endswith("amd64.deb"):
				print(asset.get("browser_download_url", ""))
				sys.exit(0)
except Exception as exc:
	pass
print("", end="")
sys.exit(0)
PY
	)
	if [ -n "$url" ]; then
		install_deb_from_url "Draw.io" "$url"
	else
		func_print_warn_message "Could not determine Draw.io download URL from GitHub API (rate limit or network issue)"
		func_print_info_message "Attempting fallback to known stable version..."
		install_deb_from_url "Draw.io" "https://github.com/jgraph/drawio-desktop/releases/download/v24.7.17/drawio-amd64-24.7.17.deb"
	fi
}

install_discord() {
	install_deb_from_url "Discord" "https://discord.com/api/download?platform=linux&format=deb"
}

install_telegram() {
	func_print_info_message "Installing Telegram via direct download"
	local tmpdir
	tmpdir=$(mktemp -d)
	if curl -fsSL "https://telegram.org/dl/desktop/linux" -o "$tmpdir/telegram.tar.xz"; then
		rm -rf /opt/Telegram
		mkdir -p /opt
		tar -xJf "$tmpdir/telegram.tar.xz" -C /opt
		chmod +x /opt/Telegram/Telegram
		ln -sf /opt/Telegram/Telegram /usr/local/bin/telegram-desktop
		cat > /usr/share/applications/telegram-desktop.desktop <<'EOF'
[Desktop Entry]
Name=Telegram Desktop
Comment=Official desktop client for Telegram
Exec=/opt/Telegram/Telegram -- %u
Icon=/opt/Telegram/telegram.png
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
MimeType=x-scheme-handler/tg;
EOF
		chmod 644 /usr/share/applications/telegram-desktop.desktop
		func_print_ok_message "Telegram installed under /opt/Telegram"
	else
		func_print_fail_message "Failed to download Telegram"
	fi
	rm -rf "$tmpdir"
}


apt_update

# Core development tools - NO SNAPS
apt_group_install_auto_yes "gddrescue \
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
	gedit \
	cheese \
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

# Install Microsoft Edge (high-level wrapper invocation)
./microsoft_edge.sh || func_print_warn_message "Microsoft Edge installation failed"


# Ensure hostname is in /etc/hosts
if ! grep -q "$(hostname)" /etc/hosts; then
    sudo sed -i "1i\127.0.0.1 $(hostname)" /etc/hosts
fi

# NetworkManager application moved to netplan_nm.sh (idempotent); skip here if that script ran
# If that script wasn't run, running it now is safe
if [ -x "$(dirname "$0")/netplan_nm.sh" ]; then
	"$(dirname "$0")/netplan_nm.sh" || true
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
