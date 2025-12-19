#!/bin/bash

if [ "$(id -u)" != "0" ]; then
    echo "EXIT[ERR]: need to run as root, exiting"
    exit -1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/defaults.env"

if [ -f "$DEFAULTS_FILE" ]; then
    # shellcheck disable=SC1090
    source "$DEFAULTS_FILE"
fi

detect_primary_user() {
    getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}'
}

PRIMARY_USER="$(detect_primary_user)"
CURRENT_HOSTNAME="$(hostnamectl --static 2>/dev/null || hostname)"
CURRENT_CALLER="${SUDO_USER:-$(id -un)}"

if [ -z "${DEFAULT_SUDO_USER:-}" ] && [ -n "$PRIMARY_USER" ]; then
    DEFAULT_SUDO_USER="$PRIMARY_USER"
fi
if [ -z "${DEFAULT_HOSTNAME:-}" ] && [ -n "$CURRENT_HOSTNAME" ]; then
    DEFAULT_HOSTNAME="$CURRENT_HOSTNAME"
fi

create_removal_helper() {
    local keeper="$1"
    local target="$2"
    local keeper_home
    keeper_home="$(getent passwd "$keeper" | awk -F: '{print $6}')"
    if [ -z "$keeper_home" ]; then
        echo "Could not determine ${keeper}'s home to schedule removal of ${target}." >&2
        return 1
    fi
    local script_path="${keeper_home}/remove_${target}.sh"
    cat >"$script_path" <<EOF
#!/bin/bash
set -e
sudo userdel -rf ${target}
EOF
    chown "$keeper:$keeper" "$script_path"
    chmod 750 "$script_path"
    echo "Run ~/${script_path##*/} after logging in as ${keeper} to remove ${target}."
}

maybe_remove_bootstrap_user() {
    local target="$1"
    local keeper="$2"
    if [ -z "$target" ] || [ "$target" = "root" ] || [ "$target" = "$keeper" ]; then
        return
    fi
    if ! id "$target" >/dev/null 2>&1; then
        return
    fi
    read -p "Remove bootstrap sudo user '${target}'? [y/N]: " remove_now
    if [[ ! "$remove_now" =~ ^[Yy]$ ]]; then
        return
    fi
    if [ "$target" = "$CURRENT_CALLER" ]; then
        echo "Cannot remove ${target} while this session is running as that user; queuing helper script for ${keeper}."
        create_removal_helper "$keeper" "$target"
        return
    fi
    userdel -rf "$target"
    echo "Removed ${target}."
}

source "${SCRIPT_DIR}/common_bash_funcs.sh"

# point /bin/sh to bash
ln -sf /bin/bash /bin/sh

mod_requires_reboot="0"
default_account="${DEFAULT_SUDO_USER:-${SUDO_USER:-${PRIMARY_USER:-}}}"
display_default="${default_account:-current user}"
HOSTNAME_DISPLAY="${CURRENT_HOSTNAME:-${DEFAULT_HOSTNAME:-unknown}}"

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

    read -n 1 -s -r -p "Press enter to continue..."
    echo ""
else
    admin_username="${SUDO_USER:-$default_account}"
fi

if id "$admin_username" >/dev/null 2>&1; then
    read -p "Set/Update password for ${admin_username}? [Y/n]: " change_admin_pass || true
    if [[ ! "$change_admin_pass" =~ ^[Nn]$ ]]; then
        passwd "$admin_username"
    fi
fi

maybe_remove_bootstrap_user "$default_account" "$admin_username"

echo "current hostname: ${HOSTNAME_DISPLAY}"
read -p "Enter new hostname [leave empty to keep ${HOSTNAME_DISPLAY}]: " hostname_new
if [ -n "$hostname_new" ]; then
    mod_requires_reboot="1"
    hostnamectl set-hostname "$hostname_new"
    CURRENT_HOSTNAME="$(hostnamectl --static 2>/dev/null || hostname)"
    echo "new hostname: ${CURRENT_HOSTNAME}"
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
