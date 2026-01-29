#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

apt_upgrade
apt_group_install_auto_yes  "curl \
	vim \
	git \
	lsb-release tree \
	ubuntu-drivers-common \
	bsdmainutils \
	linux-headers-generic \
	gdb-multiarch \
	gdebi-core \
	figlet \
	pdfgrep \
	ssh sshfs cifs-utils \
	xz-utils \
	apt-transport-https dirmngr \
	openvpn resolvconf \
	git mercurial \
	subversion \
	git-svn \
	git-lfs \
	doxygen \
	build-essential \
	make \
	perl \
	locate \
	ccache \
	clang \
	clang-format \
	ansible \
	default-jdk default-jre \
	pm-utils \
	python3 python3-pip python3-venv \
	python3-bandit \
	ipython3 \
	pv \
	minicom microcom \
	gnupg2 \
	zlib1g-dev \
	genisoimage \
	apt-transport-https \
	ca-certificates \
	curl \
	gnupg-agent \
	software-properties-common \
	lsb-release \
	isolinux \
	parted util-linux e2fsprogs \
	xorriso dumpet squashfs-tools \
	qemu-system qemu-kvm ovmf \
	traceroute \
	net-tools \
	nvme-cli \
	nodejs npm \
	libnl-3-dev libnl-genl-3-dev libnl-nf-3-dev libnl-route-3-dev \
	dos2unix parallel \
	jq keychain \
	kpartx dosfstools xxd \
	nmap \
	gawk \
	diffstat \
	unzip \
	texinfo \
	chrpath \
	gcc-multilib \
	socat \
	cpio \
	python3-pexpect \
	xz-utils \
	debianutils \
	iputils-ping \
	python3-git \
	python3-jinja2 \
	libegl1-mesa-dev \
	libsdl1.2-dev \
	tftp-hpa \
	htop \
	cpufrequtils \
	gh \
	ruby-full"
	
mkdir -p /tftpboot && chmod 777 /tftpboot && chown nobody:$SUDO_USER /tftpboot

# mkusb - check if available for 24.04
if apt-cache show mkusb >/dev/null 2>&1; then
	apt_group_install_auto_yes "mkusb mkusb-nox usb-pack-efi" "--install-recommends"
else
	func_print_warn_message "mkusb not available in repos, skipping"
fi

# Speed test tools - now via apt instead of snap
apt_install_auto_yes speedtest-cli

sudo sed -ri 's@#(DefaultTimeoutStopSec=).*@\110s@' /etc/systemd/system.conf
systemctl daemon-reload

# Bash language server
npm i -g bash-language-server
func_print_info_message "finished npm bash-language-server"

# Python tools via pipx (better isolation than pip3 install --user)
apt_install_auto_yes pipx
sudo -u $SUDO_USER pipx ensurepath

admin_username="$SUDO_USER"

# Install Python development tools
sudo -u $admin_username pipx install cpplint || func_print_warn_message "cpplint install failed"
sudo -u $admin_username pipx install pylint || func_print_warn_message "pylint install failed"
sudo -u $admin_username pipx install jira || func_print_warn_message "jira install failed"

# Ensure binaries are accessible
export PATH="$PATH:/home/$admin_username/.local/bin"
echo 'export PATH="$PATH:$HOME/.local/bin"' >> /home/$admin_username/.bashrc

func_print_info_message "finished python tools via pipx"

# Ruby gems
gem install nokogiri
func_print_info_message "finished nokogiri"

# Blacklist floppy
sudo rmmod floppy >/dev/null 2>&1
echo "blacklist floppy" | sudo tee /etc/modprobe.d/blacklist-floppy.conf
sudo dpkg-reconfigure initramfs-tools

ruby -v
python3 -V

func_print_info_message "script end `basename "$0"`"
exit 0
