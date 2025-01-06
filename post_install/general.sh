#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

#add_ppa gezakovacs/ppa ansible/ansible mkusb/ppa

apt_upgrade
apt_group_install_auto_yes  "curl \
	vim \
	git \
	lsb-core tree \
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
	python3 python3-pip \
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
	qemu qemu-kvm ovmf \
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
	libegl1-mesa \
	libsdl1.2-dev \
	tftp \
	ruby-full"
	
mkdir /tftpboot && chmodd 777 /tftpboot && chown nobody:$SUDO_USER /tftpboot

apt_group_install_auto_yes "mkusb mkusb-nox usb-pack-efi" "--install-recommends"

# disable ookla speedtest-cli as it hasn't got the release deb for some ubuntu versions 
## install ookla speed test cli
# export INSTALL_KEY=379CE192D401AB61
# export DEB_DISTRO=$(lsb_release -sc)
# sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $INSTALL_KEY
# add_to_sources_list "https://ookla.bintray.com/debian" "main"
# apt_update
# apt_install_auto_yes speedtest

snap_group_install "speed-test fast pdftk ffmpeg canonical-livepatch"
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
sudo ln -sf /home/$admin_username/.local/bin/pylint /usr/bin/pylint
func_print_info_message "finished pylint"

sudo -u $admin_username pip3 install json-spec

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
