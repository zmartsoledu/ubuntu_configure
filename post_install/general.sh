#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

add_ppa gezakovacs/ppa ansible/ansible mkusb/ppa alessandro-strada/ppa

# snap version of nmap has some issues, so, remove it first
sudo snap remove nmap 2>/dev/null

apt_upgrade
apt_group_install_auto_yes  "curl \
	lsb-core tree \
	ubuntu-drivers-common \
	bsdmainutils \
	linux-headers-generic \
	gdb-multiarch \
	gdebi-core \
	unetbootin \
	flex \
	blktrace \
	golang-go \
	nmap \
	whois \
	irpas \
	netcat \
	socat \
	hashcat \
	netdiscover \
	arp-scan \
	arping \
	telnet \
	nikto \
	libcurl4-openssl-dev \
	libxml2 \
	libxml2-dev \
	libxslt1-dev \
	ruby-dev \
	build-essential \
	libgmp-dev \
	snmp \
	medusa \
	figlet \
	pdfgrep \
	ssh sshfs cifs-utils \
	apt-transport-https dirmngr \
	openvpn resolvconf \
	git mercurial \
	doxygen \
	clang \
	ansible \
	default-jdk default-jre \
	maven \
	pm-utils \
	python3 python3-pip \
	python3-bandit \
	vim-python-jedi \
	exuberant-ctags \
	ack-grep \
	ncftp \
	pep8 \
	flake8 \
	pyflakes \
	isort \
	yapf \
	pv \
	minicom microcom \
	gnupg2 \
	zlib1g-dev \
	genisoimage \
	isolinux \
	parted util-linux e2fsprogs \
	xorriso dumpet squashfs-tools \
	qemu qemu-kvm ovmf \
	traceroute \
	node.js npm \
	libnl-3-dev libnl-genl-3-dev libnl-nf-3-dev libnl-route-3-dev \
	dos2unix parallel \
	jq keychain \
	kpartx dosfstools xxd \
	smbclient \
	google-drive-ocamlfuse \
	ruby-full"

apt_group_install_auto_yes "mkusb mkusb-nox usb-pack-efi" "--install-recommends"

sudo curl -L https://yt-dl.org/latest/youtube-dl -o /usr/bin/youtube-dl && sudo chmod 755 /usr/bin/youtube-dl

# disable ookla speedtest-cli as it hasn't got the release deb for some ubuntu versions 
## install ookla speed test cli
# export INSTALL_KEY=379CE192D401AB61
# export DEB_DISTRO=$(lsb_release -sc)
# sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $INSTALL_KEY
# add_to_sources_list "https://ookla.bintray.com/debian" "main"
# apt_update
# apt_install_auto_yes speedtest

snap_group_install "speed-test fast pdftk ffmpeg canonical-livepatch gobuster-csal pick-colour-picker"
snap_install "powershell" "--classic"

sudo sed -ri 's@#(DefaultTimeoutStopSec=).*@\110s@' /etc/systemd/system.conf | grep "DefaultTimeoutStopSec"

npm i -g bash-language-server
func_print_info_message "finished npm bash-language-server"

admin_username="$SUDO_USER"
sudo -u $admin_username pip3 install cpplint
sudo ln -sf /home/$admin_username/.local/bin/cpplint /usr/bin/cpplint
func_print_info_message "finished cpplint"

sudo -u $admin_username pip3 install jira urllib3 beautifulsoup4 lxml
sudo -u $admin_username pip3 install pylint
sudo -u $admin_username pip3 install pyftpdlib
sudo ln -sf /home/$admin_username/.local/bin/pylint /usr/bin/pylint
func_print_info_message "finished pylint"

# install ruby version manager
#curl -sSL https://rvm.io/mpapis.asc | gpg2 --import -
#curl -sSL https://rvm.io/pkuczynski.asc | gpg2 --import -

#curl -sSL https://get.rvm.io -o rvm.sh
#cat rvm.sh | bash -s stable

#rvm install ruby --disable-binary
#rm -f rvm.sh

gem install nokogiri
func_print_info_message "finished nokogiri"

sudo rmmod floppy >/dev/null 2>&1
echo "blacklist floppy" | sudo tee /etc/modprobe.d/blacklist-floppy.conf
sudo dpkg-reconfigure initramfs-tools

ruby -v

func_print_info_message "script end `basename "$0"`"
exit 0
