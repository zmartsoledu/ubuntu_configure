#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

echo "downloading the daily snapshot of pci ids database"
update-pciids

apt_install_auto_yes lshw
echo "attempting to list the available display devices via lshw"
lshw -C display

graphics_card_vendor_and_model=`lspci -v | less | grep "VGA" | grep -Ei "nvidia|amd" | sed 's@.*controller: \(.*\)@\1@'`
# change to lovercase
graphics_card_vendor_and_model=`echo ${graphics_card_vendor_and_model,,}`
printf "\n identified graphics card: $graphics_card_vendor_and_model\n"

add_ppa graphics-drivers/ppa
apt_update
if `echo $graphics_card_vendor_and_model | grep "nvidia" > /dev/null 2>&1`; then
	echo "identified graphics card: nvidia, going ahead with the installation"

	echo "blacklisting nouveau"
	bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
	bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
	update-initramfs -u

	apt-get purge -y nvidia*

	latest_nvidia_pkg=`apt-cache search nvidia- | grep -E "^nvidia-driver-[0-9]{3,5}-server " | cut -d" " -f1 | sort -V | uniq | tail -n1`

	if [ -z "$latest_nvidia_pkg" ]; then
		latest_nvidia_pkg=`apt-cache search nvidia- | grep -E "^nvidia-driver-[0-9]{3,5} " | cut -d" " -f1 | sort -V | uniq | tail -n1`
	fi

	if [ -z "$latest_nvidia_pkg" ]; then
		echo "falling back to ubuntu-driver to identify the latest driver, please wait..."
		latest_nvidia_pkg=`ubuntu-driver devices | grep "non-free" | grep -Eo "nvidia-driver-[0-9]{3,4}" | sort -V | uniq | tail -n1`
	fi
	echo "attempting to install: $latest_nvidia_pkg"

	if [ ! -z "$latest_nvidia_pkg" ]; then
		apt_group_install_auto_yes "$latest_nvidia_pkg nvidia-modprobe"
	else
		echo "cannot identify the nvidia package, trying auto install"
		ubuntu-drivers autoinstall
	fi

	echo "installed nvidia system info: "
	nvidia-smi
	apt_group_install_auto_yes "nvidia-settings"

elif `echo $graphics_card_vendor_and_model | grep "amd" > /dev/null 2>&1`; then
	echo "identified graphics card: amd, going ahead with the installation"

	add_ppa oibaf/graphics-drivers
	apt_update

	apt_install_auto_yes xserver-xorg-video-amdgpu "--reinstall"
	dpkg --configure -a
	dpkg-reconfigure gdm3 ubuntu-session xserver-xorg-video-amdgpu

	apt_install_auto_yes mesa-vdpau-drivers

	printf -- "Section \"Device\"\n\tIdentifier \"AMDGPU\"\n\tDriver \"amdgpu\"\n\tOption \"AccelMethod\" \"glamor\"\n\tOption \"DRI\" \"3\"\nEndSection\n" >> /etc/X11/xorg.conf
else
	echo "identified graphics card: unhandled, exiting"
fi

func_print_info_message "script end `basename "$0"`"
echo ""
