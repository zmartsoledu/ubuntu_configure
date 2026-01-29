#!/bin/bash

# LUKS Auto-Unlock Script for Ubuntu 24.04
# Enables auto-decryption via USB key or YubiKey, with fallback to password prompt

if [ `id -u` != "0" ]; then
	echo "EXIT[ERR]: need to run as root, exiting"
	exit 1
fi

set -e

COL_GRN="\e[32m"
COL_RED="\e[31m"
COL_YEL="\e[33m"
COL_DFL="\e[39m"

print_info() {
    echo -e "${COL_GRN}[INFO]${COL_DFL} $1"
}

print_error() {
    echo -e "${COL_RED}[ERROR]${COL_DFL} $1"
}

print_warn() {
    echo -e "${COL_YEL}[WARN]${COL_DFL} $1"
}

# Detect encrypted device
LUKS_DEV=$(blkid | grep crypto_LUKS | head -n1 | cut -d: -f1)

if [ -z "$LUKS_DEV" ]; then
    print_error "No LUKS encrypted device found"
    exit 1
fi

print_info "Found LUKS device: $LUKS_DEV"

# Get device UUID
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_DEV")
print_info "LUKS UUID: $LUKS_UUID"

# Menu for unlock method
echo ""
echo "Select unlock method:"
echo "1) USB key (keyfile on external USB)"
echo "2) YubiKey (challenge-response)"
echo "3) Remove auto-unlock (password only)"
read -p "Choice [1-3]: " CHOICE

case $CHOICE in
    1)
        # USB Keyfile method
        print_info "=== USB Keyfile Setup ==="
        read -p "Insert USB drive and press Enter..."
        
        # List available USB devices
        print_info "Available USB devices:"
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "sd[b-z]|part"
        
        read -p "Enter USB device (e.g., sdb1): " USB_DEV
        USB_DEV="/dev/$USB_DEV"
        
        if [ ! -b "$USB_DEV" ]; then
            print_error "Device $USB_DEV not found"
            exit 1
        fi
        
        # Mount USB
        MOUNT_POINT="/mnt/usb_key"
        mkdir -p "$MOUNT_POINT"
        mount "$USB_DEV" "$MOUNT_POINT" 2>/dev/null || {
            print_error "Failed to mount $USB_DEV"
            exit 1
        }
        
        # Generate keyfile
        KEYFILE="$MOUNT_POINT/.luks_keyfile"
        print_info "Generating keyfile..."
        dd if=/dev/urandom of="$KEYFILE" bs=512 count=8
        chmod 000 "$KEYFILE"
        
        # Add keyfile to LUKS
        print_info "Adding keyfile to LUKS device (enter current password)..."
        cryptsetup luksAddKey "$LUKS_DEV" "$KEYFILE"
        
        # Get USB UUID for fstab
        USB_UUID=$(blkid -s UUID -o value "$USB_DEV")
        
        # Create crypttab entry
        MAPPED_NAME=$(grep "$LUKS_UUID" /etc/crypttab | awk '{print $1}' | head -n1)
        if [ -z "$MAPPED_NAME" ]; then
            MAPPED_NAME="luks-$LUKS_UUID"
        fi
        
        # Backup crypttab
        cp /etc/crypttab /etc/crypttab.backup
        
        # Update crypttab
        cat > /etc/crypttab << EOF
# Auto-unlock with USB keyfile, fallback to password
$MAPPED_NAME UUID=$LUKS_UUID none luks,keyscript=/lib/cryptsetup/scripts/passdev
EOF
        
        # Create passdev script
        cat > /lib/cryptsetup/scripts/passdev << 'EOSCRIPT'
#!/bin/sh
# Try to mount USB and read keyfile, fallback to password prompt

USB_UUID="USB_UUID_PLACEHOLDER"
KEYFILE=".luks_keyfile"

# Wait for USB device
for i in $(seq 1 10); do
    USB_DEV=$(blkid -U "$USB_UUID" 2>/dev/null)
    [ -n "$USB_DEV" ] && break
    sleep 1
done

if [ -n "$USB_DEV" ]; then
    MOUNT_POINT="/tmp/usb_unlock"
    mkdir -p "$MOUNT_POINT"
    
    if mount -r "$USB_DEV" "$MOUNT_POINT" 2>/dev/null; then
        if [ -f "$MOUNT_POINT/$KEYFILE" ]; then
            cat "$MOUNT_POINT/$KEYFILE"
            umount "$MOUNT_POINT" 2>/dev/null
            exit 0
        fi
        umount "$MOUNT_POINT" 2>/dev/null
    fi
fi

# Fallback to password prompt
/lib/cryptsetup/askpass "Enter passphrase for $CRYPTTAB_SOURCE: "
EOSCRIPT
        
        # Replace placeholder with actual USB UUID
        sed -i "s/USB_UUID_PLACEHOLDER/$USB_UUID/" /lib/cryptsetup/scripts/passdev
        chmod +x /lib/cryptsetup/scripts/passdev
        
        umount "$MOUNT_POINT"
        
        print_info "USB keyfile setup complete!"
        print_warn "Keep this USB drive safe - it can unlock your disk!"
        print_info "Boot will fall back to password if USB is not present"
        ;;
        
    2)
        # YubiKey method
        print_info "=== YubiKey Challenge-Response Setup ==="
        
        # Check if yubikey packages are installed
        if ! dpkg -l | grep -q yubikey-luks; then
            print_info "Installing YubiKey packages..."
            apt-get update
            apt-get install -y yubikey-luks yubikey-personalization
        fi
        
        print_info "Insert YubiKey and press Enter..."
        read
        
        # Initialize YubiKey for LUKS
        print_info "Configuring YubiKey (enter current LUKS password when prompted)..."
        yubikey-luks-enroll -d "$LUKS_DEV" -s 2
        
        print_info "YubiKey setup complete!"
        print_warn "Keep YubiKey safe - you'll need it + PIN to unlock"
        ;;
        
    3)
        # Remove auto-unlock
        print_info "=== Removing Auto-Unlock ==="
        
        # Restore password-only crypttab
        MAPPED_NAME=$(grep "$LUKS_UUID" /etc/crypttab | awk '{print $1}' | head -n1)
        if [ -z "$MAPPED_NAME" ]; then
            MAPPED_NAME="luks-$LUKS_UUID"
        fi
        
        cat > /etc/crypttab << EOF
$MAPPED_NAME UUID=$LUKS_UUID none luks
EOF
        
        print_info "Auto-unlock removed. System will prompt for password on boot."
        ;;
        
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

# Update initramfs
print_info "Updating initramfs..."
update-initramfs -u -k all

print_info "Done! Reboot to test."
print_warn "Make sure you can still unlock manually before removing old keyslots!"

exit 0
