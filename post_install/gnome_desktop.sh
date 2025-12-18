#!/bin/bash

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

sudo apt --fix-broken install

# Ubuntu 24.04: ubuntu-gnome-desktop is deprecated
# Use ubuntu-desktop-minimal for clean GNOME without snap bloat
echo "Installing minimal GNOME desktop..."

apt_install_auto_yes "ubuntu-desktop-minimal" "--no-install-recommends"

# Add essential GNOME tools
apt_group_install_auto_yes "gnome-tweaks gnome-shell-extensions \
    gnome-terminal nautilus gnome-control-center \
    gnome-system-monitor gnome-calculator \
    gnome-disk-utility file-roller"

# Optional: Remove snap firefox if it got installed
snap list 2>/dev/null | grep firefox >/dev/null && {
    func_print_info_message "Removing snap firefox..."
    snap remove --purge firefox
}

sudo apt --fix-broken install

echo "current display manager: "
func_print_info_message "current display manager: `cat /etc/X11/default-display-manager`"

# Ensure GDM is the display manager
if [ ! -f /etc/X11/default-display-manager ] || ! grep -q gdm /etc/X11/default-display-manager; then
    echo "/usr/sbin/gdm3" > /etc/X11/default-display-manager
    func_print_info_message "Set GDM3 as default display manager"
fi

func_print_info_message "script end `basename "$0"`"
