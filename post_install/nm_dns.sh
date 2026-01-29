#!/bin/sh

#!/bin/sh

if [ "$(id -u)" != "0" ]; then
    echo "EXIT[ERR]: need to run as root"
    exit 1
fi

# Ensure NetworkManager config exists
NM_CONF="/etc/NetworkManager/NetworkManager.conf"
[ -f "$NM_CONF" ] || exit 0

# Ensure NM uses systemd-resolved
if ! grep -q '^dns=systemd-resolved' "$NM_CONF"; then
    sed -i '/^dns=/d' "$NM_CONF"
    sed -i '/^\[main\]/a dns=systemd-resolved' "$NM_CONF"
fi

# Enable and start systemd-resolved
systemctl enable --now systemd-resolved

# Fix resolv.conf symlink (idempotent)
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Restart NM to re-register DNS
systemctl restart NetworkManager
