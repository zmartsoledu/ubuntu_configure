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

graphics_card_vendor_and_model=`lspci -v | less | grep "VGA" | grep -Ei "nvidia|amd|intel" | sed 's@.*controller: \(.*\)@\1@'`
# change to lowercase
graphics_card_vendor_and_model=`echo ${graphics_card_vendor_and_model,,}`
printf "\n identified graphics card: $graphics_card_vendor_and_model\n"

if `echo $graphics_card_vendor_and_model | grep "nvidia" > /dev/null 2>&1`; then
	echo "identified graphics card: nvidia, going ahead with the installation"

	add_ppa graphics-drivers/ppa
	apt_update

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
		latest_nvidia_pkg=`ubuntu-drivers devices | grep "non-free" | grep -Eo "nvidia-driver-[0-9]{3,4}" | sort -V | uniq | tail -n1`
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

	# Ubuntu 24.04 has excellent AMD support in main repos, no PPA needed
	apt_update

	apt_install_auto_yes xserver-xorg-video-amdgpu "--reinstall"
	dpkg --configure -a
	dpkg-reconfigure gdm3 ubuntu-session xserver-xorg-video-amdgpu

	# Install mesa and vulkan drivers
	apt_group_install_auto_yes "mesa-vulkan-drivers mesa-vdpau-drivers libgl1-mesa-dri libglx-mesa0"

	# ROCm for compute workloads (optional, heavy)
	# apt_group_install_auto_yes "rocm-hip-runtime rocm-opencl-runtime"

	printf -- "Section \"Device\"\n\tIdentifier \"AMDGPU\"\n\tDriver \"amdgpu\"\n\tOption \"AccelMethod\" \"glamor\"\n\tOption \"DRI\" \"3\"\n\tOption \"TearFree\" \"true\"\nEndSection\n" >> /etc/X11/xorg.conf

elif `echo $graphics_card_vendor_and_model | grep "intel" > /dev/null 2>&1`; then
	echo "identified graphics card: intel, going ahead with the installation"

	# Check for Intel Arc (Alchemist/Battlemage)
	if lspci | grep -iE "arc|dg2|alchemist" > /dev/null 2>&1; then
		echo "Intel Arc detected - installing enhanced drivers"
		
		# Intel Arc needs kernel 6.2+ (24.04 has 6.8+, so we're good)
		apt_group_install_auto_yes "intel-gpu-tools intel-media-va-driver-non-free mesa-vulkan-drivers vulkan-tools"
		
		# Intel compute runtime for OpenCL
		apt_group_install_auto_yes "intel-opencl-icd ocl-icd-opencl-dev"
		
		# Level Zero for compute
		apt_group_install_auto_yes "level-zero-loader level-zero-devel"
		
		func_print_ok_message "Intel Arc drivers installed"
		func_print_info_message "Test with: intel_gpu_top, vulkaninfo, clinfo"
	else
		echo "Intel integrated graphics detected"
		apt_group_install_auto_yes "intel-media-va-driver mesa-vulkan-drivers"
	fi

	# Ensure i915 GuC/HuC firmware loading is enabled
	if ! grep -q "i915.enable_guc" /etc/default/grub; then
		sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 i915.enable_guc=3"/' /etc/default/grub
		update-grub
		func_print_info_message "Enabled Intel GuC/HuC firmware loading (requires reboot)"
	fi

else
	echo "identified graphics card: unhandled or integrated, installing generic drivers"
	apt_group_install_auto_yes "mesa-vulkan-drivers libgl1-mesa-dri"
fi

func_print_info_message "script end `basename "$0"`"
echo ""
