#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

install_copilot_cli() {
	local installer_url="https://gh.io/copilot-install"
	if command -v copilot >/dev/null 2>&1; then
		func_print_info_message "Copilot CLI already installed, skipping"
		return
	fi
	func_print_info_message "Installing GitHub Copilot CLI..."
	if curl -fsSL "$installer_url" | PREFIX=/usr/local bash >/tmp/copilot-install.log 2>&1; then
		func_print_ok_message "copilot CLI installed to /usr/local/bin"
	else
		func_print_warn_message "Copilot CLI installer failed (see /tmp/copilot-install.log)"
	fi
}

provision_wireless_stack() {
	func_print_info_message "Installing Wi-Fi tooling"
	apt_group_install_auto_yes "wireless-tools wpasupplicant"

	if ! dpkg -s linux-firmware >/dev/null 2>&1; then
		apt_install_auto_yes linux-firmware
	fi

	if command -v lspci >/dev/null 2>&1 && lspci | grep -iE "(wireless|network)" | grep -qi intel; then
		func_print_info_message "Intel Wi-Fi detected, ensuring firmware"
		apt_install_auto_yes firmware-iwlwifi || apt_install_auto_yes linux-firmware
	fi

	func_print_info_message "Installing Bluetooth base packages"
	apt_group_install_auto_yes "bluez bluez-tools"
	systemctl enable bluetooth
	systemctl start bluetooth
	# Ensure DHCP client is available for manual DHCP bring-up
	apt_install_auto_yes "isc-dhcp-client"
}

# point /bin/sh to bash
ln -sf /bin/bash /bin/sh

# add some aliases
if [ ! -s ~/.bash_aliases ]; then
	cat bash_aliases >> ~/.bash_aliases
fi

echo '#!/bin/bash' > run_manually.sh
echo "sudo sed -ri 's@^#WaylandEnable@WaylandEnable@' /etc/gdm3/custom.conf > /dev/null 2>&1" >> run_manually.sh
echo "sudo sed -ri 's@\"quiet\"@\"\"@' /etc/default/grub > /dev/null 2>&1" >> run_manually.sh
echo "sudo update-grub" >> run_manually.sh

./check_sshd_status.sh
./general.sh
./docker.sh
./azure.sh
./groups.sh

install_copilot_cli
provision_wireless_stack

# Configure NetworkManager/netplan after wireless stack is ready
./netplan_nm.sh || true

# VirtualBox - check if needed for 24.04
func_print_info_message "VirtualBox - skipped, consider alternatives (libvirt/qemu)"
# ./virtualbox.sh

# Vagrant - now using libvirt as provider instead of VirtualBox
./vagrant.sh
./libvirt_kvm.sh

# Vagrant plugins for libvirt
func_print_info_message "Installing vagrant-libvirt plugin"
vagrant plugin install vagrant-libvirt

./disk_man.sh

echo "removing i386 packages, please wait..."
apt-get purge ".*:i386" -y > /dev/null 2>&1
echo "continuing to remove i386 packages, please wait..."
dpkg --remove-architecture i386 > /dev/null 2>&1

if [ -f "run_manually.sh" ]; then
	chmod 755 run_manually.sh
	./run_manually.sh
fi

func_print_info_message "script end `basename "$0"`"

echo "server extras are completed. please restart your pc and continue with the pre-graph setup"

exit 0
