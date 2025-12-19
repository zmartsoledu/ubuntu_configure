#!/bin/bash

# Laptop-specific configuration for Ubuntu 24.04
# WiFi, Bluetooth, Power Management, Suspend, Lid behavior

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

print_info() {
    func_print_info_message "$1"
}

echo "========================================"
echo "    Laptop Configuration Script"
echo "========================================"
echo ""

# Detect if this is a laptop
IS_LAPTOP=0
if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
	IS_LAPTOP=1
	print_info "Battery detected - configuring laptop features"
else
	print_info "No battery detected - some features may not be relevant"
fi

# Power Management - TLP
print_info "Installing TLP for power management..."
apt_update
apt_group_install_auto_yes "tlp tlp-rdw powertop"

# Start and enable TLP
systemctl enable tlp
systemctl start tlp

# Configure TLP for balanced power/performance
if [ ! -f /etc/tlp.conf.backup ]; then
	cp /etc/tlp.conf /etc/tlp.conf.backup
fi

# Adjust TLP settings
cat >> /etc/tlp.conf << 'EOF'

# Custom settings for balanced laptop use
TLP_DEFAULT_MODE=BAT
TLP_PERSISTENT_DEFAULT=0

CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=powersave

CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power

CPU_MIN_PERF_ON_AC=0
CPU_MAX_PERF_ON_AC=100
CPU_MIN_PERF_ON_BAT=0
CPU_MAX_PERF_ON_BAT=50

STOP_CHARGE_THRESH_BAT0=80
STOP_CHARGE_THRESH_BAT1=80
EOF

tlp start
func_print_ok_message "TLP configured and started"

# WiFi tweaks (drivers installed during Stage 1 server extras)
print_info "Applying WiFi power optimizations..."
if [ ! -f /etc/NetworkManager/conf.d/wifi-powersave.conf ]; then
	mkdir -p /etc/NetworkManager/conf.d/
	cat > /etc/NetworkManager/conf.d/wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave = 2
EOF
	func_print_ok_message "WiFi power saving configured"
else
	func_print_info_message "WiFi power saving file already present"
fi

# Bluetooth service (bluez core installed during Stage 1)
print_info "Ensuring Bluetooth service is active..."
apt_group_install_auto_yes "blueman"
systemctl enable bluetooth
systemctl start bluetooth
func_print_ok_message "Bluetooth service running"

# Suspend and Hibernate
print_info "Configuring suspend/hibernate..."

# Enable suspend on lid close
if [ ! -f /etc/systemd/logind.conf.backup ]; then
	cp /etc/systemd/logind.conf /etc/systemd/logind.conf.backup
fi

sed -i 's/#HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
sed -i 's/#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
sed -i 's/#LidSwitchIgnoreInhibited=.*/LidSwitchIgnoreInhibited=no/' /etc/systemd/logind.conf

# Disable suspend on idle when plugged in (keep awake for development)
if [ -f /etc/UPower/UPower.conf ]; then
	if [ ! -f /etc/UPower/UPower.conf.backup ]; then
		cp /etc/UPower/UPower.conf /etc/UPower/UPower.conf.backup
	fi
	sed -i 's/IgnoreInhibitors=.*/IgnoreInhibitors=true/' /etc/UPower/UPower.conf
fi

systemctl restart systemd-logind

func_print_ok_message "Suspend/lid behavior configured"

# Touchpad gestures (if using Wayland)
if [ "$XDG_SESSION_TYPE" == "wayland" ] || ps aux | grep -i wayland >/dev/null; then
	print_info "Installing touchpad gesture support..."
	apt_group_install_auto_yes "libinput-tools xdotool wmctrl"
	
	# Install libinput-gestures
	if ! which libinput-gestures >/dev/null 2>&1; then
		cd /tmp
		git clone https://github.com/bulletmark/libinput-gestures.git
		cd libinput-gestures
		make install
		cd ..
		rm -rf libinput-gestures
		
		# Add user to input group
		usermod -aG input $SUDO_USER
		
		func_print_ok_message "Touchpad gestures installed (configure with: libinput-gestures-setup)"
	fi
fi

# Backlight control
print_info "Installing backlight control..."
apt_install_auto_yes "brightnessctl"

# Allow user to control backlight without sudo
if [ ! -f /etc/udev/rules.d/90-brightnessctl.rules ]; then
	cat > /etc/udev/rules.d/90-brightnessctl.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video $sys$devpath/brightness", RUN+="/bin/chmod g+w $sys$devpath/brightness"
ACTION=="add", SUBSYSTEM=="leds", RUN+="/bin/chgrp video $sys$devpath/brightness", RUN+="/bin/chmod g+w $sys$devpath/brightness"
EOF
	usermod -aG video $SUDO_USER
	udevadm control --reload-rules
	udevadm trigger
	func_print_ok_message "Backlight control configured"
fi

# Laptop Mode Tools (alternative to TLP, don't use both)
# Commented out since we're using TLP
# apt_install_auto_yes "laptop-mode-tools"

# Display auto-rotation (for 2-in-1 devices)
if which iio-sensor-proxy >/dev/null 2>&1; then
	print_info "Accelerometer sensor detected"
	apt_install_auto_yes "iio-sensor-proxy"
else
	print_info "No accelerometer detected, skipping auto-rotation"
fi

# Battery threshold (for supported laptops)
if [ -f /sys/class/power_supply/BAT0/charge_control_end_threshold ] 2>/dev/null; then
	print_info "Battery charge threshold supported"
	echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold
	func_print_ok_message "Battery charge threshold set to 80%"
fi

# Disable USB autosuspend for problematic devices (uncomment if needed)
# echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="XXXX", ATTR{idProduct}=="YYYY", ATTR{power/autosuspend}="-1"' > /etc/udev/rules.d/50-usb-power.rules

print_info "Laptop configuration complete!"
echo ""
print_info "Summary:"
print_info "  ✓ TLP power management installed and configured"
print_info "  ✓ WiFi power savings & Bluetooth service tuned"
print_info "  ✓ Suspend on lid close configured"
print_info "  ✓ Backlight control enabled"
if [ $IS_LAPTOP -eq 1 ]; then
	print_info "  ✓ Battery optimizations applied"
fi
echo ""
print_info "Useful commands:"
print_info "  tlp-stat              - View TLP status"
print_info "  tlp-stat -b           - View battery info"
print_info "  powertop              - Power consumption analyzer"
print_info "  brightnessctl         - Control screen brightness"
print_info "  nmcli device wifi     - Manage WiFi"
print_info "  bluetoothctl          - Manage Bluetooth"

func_print_info_message "script end `basename "$0"`"
exit 0
