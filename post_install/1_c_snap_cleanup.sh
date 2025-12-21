#!/bin/bash

# Snap & Flatpak removal for Ubuntu 24.04
# Run immediately after first-boot hardening so the rest of the stack stays snap/flatpak-free

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit -1
fi

source ./common_bash_funcs.sh

COL_GRN="\e[32m"
COL_RED="\e[31m"
COL_YEL="\e[33m"
COL_DFL="\e[39m"

print_warn() {
    echo -e "${COL_YEL}[WARN]${COL_DFL} $1"
}

print_info() {
    echo -e "${COL_GRN}[INFO]${COL_DFL} $1"
}

echo "========================================"
echo "    Snap & Flatpak Removal"
echo "========================================"
echo ""
print_warn "This will remove ALL snap packages, snapd, and any flatpak remnants"
print_warn "Continue only if you are committed to a snap/flatpak-free system"
echo ""

# Detect snap/flatpak availability
snap_present=0
if command -v snap >/dev/null 2>&1; then
	snap_present=1
else
	print_info "snap command not found; continuing with snapd purge"
fi

# List current snaps
if [ "$snap_present" -eq 1 ]; then
	print_info "Current snap packages:"
	snap list | tee /root/snap_list_backup.txt
	echo ""
else
	print_info "No snap packages detected"
fi

read -p "Do you want to proceed with snap removal? [y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
	print_info "Aborting snap removal"
	exit 0
fi

if [ "$snap_present" -eq 1 ]; then
	# Remove all snap packages
	print_info "Removing snap packages..."
	for snap in $(snap list | awk 'NR>1 {print $1}'); do
		print_info "Removing snap: $snap"
		snap remove --purge "$snap" 2>/dev/null || {
			print_warn "Failed to remove $snap, trying again..."
			snap remove --purge "$snap" 2>&1
		}
	done

	# Remove core snaps (order matters)
	for core_snap in lxd core20 core22 core24 bare snapd; do
		if snap list 2>/dev/null | grep "^$core_snap " >/dev/null; then
			print_info "Removing core snap: $core_snap"
			snap remove --purge "$core_snap" 2>/dev/null
		fi
	done
else
	print_info "Skipping snap package removal step"
fi

# Stop snapd services (now that snaps have been removed)
print_info "Stopping snapd services..."
systemctl stop snapd.service || true
systemctl stop snapd.socket || true
systemctl stop snapd.seeded.service || true

# Remove snapd package
print_info "Removing snapd package..."
apt purge -y snapd || true
apt autoremove -y || true

# Mark snapd as held to prevent reinstallation
print_info "Marking snapd as held..."
apt-mark hold snapd >/dev/null 2>&1 || true

# Create preference file to block snapd
cat > /etc/apt/preferences.d/no-snapd << 'EOF'
Package: snapd
Pin: release *
Pin-Priority: -1
EOF

# Remove flatpak packages as well
print_info "Removing flatpak packages (if any)..."
flatpak_pkgs_to_remove=()
for pkg in flatpak gnome-software-plugin-flatpak; do
	dpkg -s "$pkg" >/dev/null 2>&1 && flatpak_pkgs_to_remove+=("$pkg")
done
if [ ${#flatpak_pkgs_to_remove[@]} -gt 0 ]; then
	apt purge -y "${flatpak_pkgs_to_remove[@]}"
	apt autoremove -y || true
else
	print_info "No flatpak packages installed"
fi
apt-mark hold flatpak >/dev/null 2>&1 || true

cat > /etc/apt/preferences.d/no-flatpak << 'EOF'
Package: flatpak
Pin: release *
Pin-Priority: -1
EOF

print_info "Cleaning up snap/flatpak directories..."
rm -rf /snap
rm -rf /var/snap
rm -rf /var/lib/snapd
rm -rf /var/cache/snapd
rm -rf /var/lib/flatpak
rm -rf /etc/flatpak
rm -rf /usr/lib/flatpak
rm -rf /usr/share/flatpak
rm -rf /home/*/snap 2>/dev/null || true
rm -rf /home/*/.local/share/flatpak 2>/dev/null || true
rm -rf ~/snap
rm -rf ~/.local/share/flatpak

# Remove snap from PATH in system-wide profile
if [ -f /etc/profile.d/apps-bin-path.sh ]; then
	rm -f /etc/profile.d/apps-bin-path.sh
fi

# Clean up any snap mount units
print_info "Cleaning up snap mount units..."
rm -f /etc/systemd/system/snap-*.mount
rm -f /etc/systemd/system/multi-user.target.wants/snap-*.mount
systemctl daemon-reload

print_info "Snap/flatpak removal complete!"
echo ""
print_info "Summary:"
print_info "  - All snap packages removed"
print_info "  - snapd package purged and held"
print_info "  - Flatpak packages removed/held"
print_info "  - Snap/flatpak directories cleaned"
if [ "$snap_present" -eq 1 ]; then
	print_info "  - Backup of snap list: /root/snap_list_backup.txt"
fi
echo ""
print_warn "Reboot recommended to ensure all snap/flatpak remnants are gone"

func_print_info_message "script end `basename "$0"`"
exit 0
