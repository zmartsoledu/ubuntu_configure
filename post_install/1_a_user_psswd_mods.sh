#!/bin/bash

if [ "$(id -u)" != "0" ]; then
    echo "EXIT[ERR]: need to run as root, exiting"
    exit -1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/defaults.env"

DEFAULT_SUDO_USER="zmartadmin"
DEFAULT_HOSTNAME="zmart-u24"
DEFAULT_LUKS_PASSPHRASE="zmart-default-luks"

if [ -f "$DEFAULTS_FILE" ]; then
    # shellcheck disable=SC1090
    source "$DEFAULTS_FILE"
fi

source "${SCRIPT_DIR}/common_bash_funcs.sh"

# point /bin/sh to bash
ln -sf /bin/bash /bin/sh

mod_requires_reboot="0"
default_account="${DEFAULT_SUDO_USER:-$SUDO_USER}"
display_default="${default_account:-current user}"

read -p "Enter username for new sudoer [leave empty to keep ${display_default}]: " admin_username
if [ -n "$admin_username" ]; then
    mod_requires_reboot="1"
    UID_OPT=""
    # if uid 1000 is free, make sure that we use it
    getent passwd 1000 >/dev/null 2>&1
    if [ "$?" != "0" ]; then
        UID_OPT="--uid 1000"
    fi

    adduser $UID_OPT --gecos "" "$admin_username"
    usermod -aG sudo "$admin_username"

    echo "created sudoer $admin_username ."
    echo "after reboot, login as $admin_username to continue setup"

    if [ -n "$default_account" ] && id "$default_account" >/dev/null 2>&1; then
        read -p "Remove default sudo user '$default_account' after first login? [y/N]: " remove_default
        if [[ "$remove_default" =~ ^[Yy]$ ]]; then
            first_boot_script="/home/$admin_username/first_boot.sh"
            cat > "$first_boot_script" <<EOT
#!/bin/bash
set -e
sudo userdel -rf ${default_account} >/dev/null 2>&1 || true
EOT
            chown "$admin_username:$admin_username" "$first_boot_script"
            chmod 750 "$first_boot_script"
            echo "After reboot, login as $admin_username and run ~/first_boot.sh to remove $default_account."
        fi
    fi

    read -n 1 -s -r -p "Press enter to continue..."
    echo ""
else
    admin_username="${SUDO_USER:-$default_account}"
fi

echo "current hostname: " "$(hostname)"
read -p "Enter new hostname [default: ${DEFAULT_HOSTNAME}], leave empty to skip: " hostname_new
if [ -n "$hostname_new" ]; then
    mod_requires_reboot="1"
    hostnamectl set-hostname "$hostname_new"
    echo "new hostname: " "$(hostname)"
fi

read -p "Do you want to change the encryption passphrase? [y/N]: " enc_psswd
if [[ "$enc_psswd" =~ ^[Yy]$ ]]; then
    mod_requires_reboot="1"
    disk_suffix=$(grep -Eo "^sd[a-z][0-9]{1,2}" /etc/crypttab | head -n1)
    disk_path="/dev/${disk_suffix}"
    if [ -b "$disk_path" ]; then
        sudo cryptsetup luksAddKey "$disk_path"
        if [ $? -eq "0" ]; then
            if [ -n "$DEFAULT_LUKS_PASSPHRASE" ]; then
                printf '%s\n' "$DEFAULT_LUKS_PASSPHRASE" | sudo cryptsetup luksRemoveKey "$disk_path" >/dev/null 2>&1
                if [ "$?" != "0" ]; then
                    echo "enter the old encryption passphrase for removal"
                    sudo cryptsetup luksRemoveKey "$disk_path"
                fi
            else
                echo "enter the old encryption passphrase for removal"
                sudo cryptsetup luksRemoveKey "$disk_path"
            fi
        fi
    fi
fi

sudo ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime

AUTO_DECRYPT_SCRIPT=""
for candidate in "${SCRIPT_DIR}/../u24.04_migration/luks_autounlock.sh" "${SCRIPT_DIR}/luks_autounlock.sh"; do
    if [ -x "$candidate" ]; then
        AUTO_DECRYPT_SCRIPT="$candidate"
        break
    fi
done

if [ -n "$AUTO_DECRYPT_SCRIPT" ]; then
    read -p "Configure automatic LUKS decryption now with $(basename "$AUTO_DECRYPT_SCRIPT")? [y/N]: " auto_unlock
    if [[ "$auto_unlock" =~ ^[Yy]$ ]]; then
        "$AUTO_DECRYPT_SCRIPT"
    else
        func_print_info_message "Run $AUTO_DECRYPT_SCRIPT later to enable USB/YubiKey auto-unlock."
    fi
else
    func_print_info_message "Auto-unlock helper not found. Copy luks_autounlock.sh locally to enable USB/YubiKey unlock later."
fi

func_print_info_message "script end $(basename "$0")"

if [ "$mod_requires_reboot" == "1" ]; then
    echo "rebooting due to username/psswd mods..."
    sleep 3
    custom_reboot
fi

exit 0
