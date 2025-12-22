#!/bin/bash
set -euo pipefail

# Snap & Flatpak removal for Ubuntu 24.04
# Run immediately after first-boot hardening so the rest of the stack stays snap/flatpak-free

if [ "$(id -u)" != "0" ]; then
    echo "EXIT[ERR]: need to run as root, exiting"
    exit 1
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

print_info "========================================"
print_info "    Snap & Flatpak Removal"
print_info "========================================"
print_warn "This will remove ALL snap packages, snapd, and any flatpak remnants"
print_warn "Continue only if you are committed to a snap/flatpak-free system"

# Detect snap/flatpak availability
snap_present=0
if command -v snap >/dev/null 2>&1; then
    snap_present=1
else
    print_info "snap command not found; continuing with snapd purge"
fi

# Backup the current snap list if possible
if [ "$snap_present" -eq 1 ]; then
    print_info "Backing up current snap list to /root/snap_list_backup.txt"
    snap list > /root/snap_list_backup.txt 2>/dev/null || true
fi

# Mask and stop snapd to reduce interference
print_info "Stopping and masking snapd services"
systemctl stop snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
systemctl mask snapd.socket snapd.service 2>/dev/null || true

# Unmount any /snap mounts and stop snap mount units
print_info "Unmounting /snap mounts and stopping snap mount units"
umount -l /snap/* 2>/dev/null || true
systemctl stop 'snap-*.mount' 2>/dev/null || true

# Detach loop devices backing snap .snap files to avoid 'device busy' errors
print_info "Detaching loop devices backing /var/lib/snapd/snaps/*.snap (if any)"
if [ -d /var/lib/snapd/snaps ]; then
    for snapfile in /var/lib/snapd/snaps/*.snap; do
        [ -f "$snapfile" ] || continue
        # losetup -j prints: /dev/loopX: [..] (file)
        for loop in $(losetup -j "$snapfile" 2>/dev/null | cut -d: -f1); do
            print_info "Detaching $loop for $snapfile"
            losetup -d "$loop" 2>/dev/null || true
        done
    done
fi

# Remove snap packages if snap command present
if [ "$snap_present" -eq 1 ]; then
    print_info "Attempting to remove snap packages (best-effort, with retries)"
    # collect snaps first to avoid subshell race with removals
    mapfile -t snaps_array < <(snap list 2>/dev/null | awk 'NR>1{print $1}') || true
    for snap in "${snaps_array[@]:-}"; do
        [ -z "$snap" ] && continue
        print_info "Removing snap: $snap"
        if snap remove --purge "$snap" 2>/dev/null; then
            print_info "Removed $snap"
            continue
        fi
        # try stopping mounts and retry
        print_warn "Initial removal failed for $snap; unmounting and retrying"
        umount -l "/snap/$snap" 2>/dev/null || true
        systemctl stop "snap.$snap.*.mount" 2>/dev/null || true
        sleep 1
        snap remove --purge "$snap" 2>/dev/null || print_warn "Failed to remove $snap"
    done

    # Try to remove core/snaps that often remain
    for core_snap in core20 core22 core24 core18 lxd bare snapd; do
        if snap list 2>/dev/null | awk 'NR>1{print $1}' | grep -xq "$core_snap"; then
            print_info "Removing core snap: $core_snap"
            snap remove --purge "$core_snap" 2>/dev/null || true
        fi
    done
else
    print_info "Skipping snap package removal step"
fi

# Final stop & mask just in case
systemctl stop snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
systemctl mask snapd.socket snapd.service 2>/dev/null || true

# Purge snapd and clean up via apt
print_info "Purging snapd package via apt"
apt-get update -y || true
apt-get purge -y snapd || true
apt-get autoremove -y || true
apt-get install -fy || true

# Prevent snapd from being reinstalled accidentally
print_info "Holding snapd package and pinning to prevent reinstallation"
apt-mark hold snapd >/dev/null 2>&1 || true
cat > /etc/apt/preferences.d/no-snapd << 'EOF'
Package: snapd
Pin: release *
Pin-Priority: -1
EOF

# Remove flatpak packages as well
print_info "Removing flatpak packages (if any)"
flatpak_pkgs_to_remove=()
for pkg in flatpak gnome-software-plugin-flatpak; do
    dpkg -s "$pkg" >/dev/null 2>&1 && flatpak_pkgs_to_remove+=("$pkg")
done
if [ ${#flatpak_pkgs_to_remove[@]} -gt 0 ]; then
    apt-get purge -y "${flatpak_pkgs_to_remove[@]}" || true
    apt-get autoremove -y || true
else
    print_info "No flatpak packages installed"
fi
apt-mark hold flatpak >/dev/null 2>&1 || true
cat > /etc/apt/preferences.d/no-flatpak << 'EOF'
Package: flatpak
Pin: release *
Pin-Priority: -1
EOF

# Clean up filesystem remnants
print_info "Cleaning up snap/flatpak directories and mount units"
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd || true
rm -rf /var/lib/flatpak /etc/flatpak /usr/lib/flatpak /usr/share/flatpak || true
rm -rf /home/*/snap 2>/dev/null || true
rm -rf /home/*/.local/share/flatpak 2>/dev/null || true
rm -f /etc/profile.d/apps-bin-path.sh || true
rm -f /etc/systemd/system/snap-*.mount || true
rm -f /etc/systemd/system/multi-user.target.wants/snap-*.mount || true
systemctl daemon-reload || true

print_info "Snap/flatpak removal complete (best-effort)"
print_info "Summary:"
print_info "  - snap packages attempted removed (see /root/snap_list_backup.txt if present)"
print_info "  - snapd package purged and pinned"
print_info "  - Flatpak packages removed/held"
print_info "  - Snap/flatpak directories cleaned"

# Verification checks
print_info "Performing verification checks for snap remnants"
fail_count=0

if command -v snap >/dev/null 2>&1; then
    print_warn "snap command still present"
    fail_count=$((fail_count+1))
else
    print_info "snap command absent"
fi

if dpkg -s snapd >/dev/null 2>&1; then
    print_warn "snapd package still installed"
    fail_count=$((fail_count+1))
else
    print_info "snapd package not installed"
fi

if mount | grep -q " /snap/"; then
    print_warn "/snap mounts still present"
    fail_count=$((fail_count+1))
else
    print_info "No /snap mounts found"
fi

if ls /var/lib/snapd/snaps 2>/dev/null | grep -q .; then
    print_warn "/var/lib/snapd/snaps still contains files"
    fail_count=$((fail_count+1))
else
    print_info "/var/lib/snapd/snaps is empty or missing"
fi

if losetup -a 2>/dev/null | grep -q "/var/lib/snapd/snaps"; then
    print_warn "Loop devices still attached to snap files"
    fail_count=$((fail_count+1))
else
    print_info "No loop devices attached to snap files"
fi

if [ "$fail_count" -eq 0 ]; then
    print_info "Verification passed: snap appears removed"
else
    print_warn "Verification detected $fail_count potential remnants; a reboot may be required and manual inspection recommended"
fi

print_warn "Reboot recommended to ensure all snap/flatpak remnants are gone"

func_print_info_message "script end $(basename "$0")"
exit 0
