#!/bin/bash
set -euo pipefail

INSTALL_DIR=${1:-}

if [ "$(id -u)" != "0" ]; then
    echo "EXIT[ERR]: need to run as root, exiting"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common_bash_funcs.sh"

if [ -z "${SUDO_USER:-}" ]; then
    func_print_fail_message "SUDO_USER not set; run this script via sudo from the target account."
    exit 1
fi

if [ -z "$INSTALL_DIR" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    INSTALL_DIR="${USER_HOME}/Anaconda"
fi
echo "$INSTALL_DIR"

func_print_info_message "Conda target directory: ${INSTALL_DIR}"

ARCHIVE_URL="https://repo.anaconda.com/archive/"
INDEX_FILE=$(mktemp)
trap 'rm -f "$INDEX_FILE"' EXIT

if ! curl -fsSL "$ARCHIVE_URL" -o "$INDEX_FILE"; then
    func_print_fail_message "Unable to reach ${ARCHIVE_URL}"
    exit 1
fi

LATEST_INSTALLER=$(grep -Po 'Anaconda3-[0-9][^"<]*-Linux-x86_64\.sh' "$INDEX_FILE" | sort -uV | tail -n1)
if [ -z "$LATEST_INSTALLER" ]; then
    LATEST_INSTALLER="Anaconda3-latest-Linux-x86_64.sh"
    func_print_warn_message "Falling back to ${LATEST_INSTALLER}"
fi

INSTALLER_URL="${ARCHIVE_URL}${LATEST_INSTALLER}"
func_print_info_message "Downloading ${INSTALLER_URL}"
rm -f Anaconda3-*-Linux-x86_64.sh
curl -fSLo "$LATEST_INSTALLER" "$INSTALLER_URL"
chmod 755 "$LATEST_INSTALLER"

SHA_FILE="${LATEST_INSTALLER}.sha256"
if curl -fsSL "${INSTALLER_URL}.sha256" -o "$SHA_FILE"; then
    func_print_info_message "Verifying download checksum"
    sha256sum --check "$SHA_FILE"
    rm -f "$SHA_FILE"
else
    func_print_warn_message "Checksum file unavailable; showing local hash"
    sha256sum "$LATEST_INSTALLER"
fi

update_flag=""
if sudo -u "$SUDO_USER" bash -lc 'command -v conda >/dev/null 2>&1'; then
    func_print_info_message "Existing conda detected, running update mode"
    update_flag="-u -f"
fi

install_cmd=("bash" "$LATEST_INSTALLER" "-b" "-p" "$INSTALL_DIR")
if [ -n "$update_flag" ]; then
    read -ra update_parts <<< "$update_flag"
    install_cmd+=("${update_parts[@]}")
fi

sudo -u "$SUDO_USER" "${install_cmd[@]}"

cat > run_manually.sh <<EOF_INSTRUCTIONS
#!/bin/bash
set -e
export PATH=\$PATH:${INSTALL_DIR}/condabin
conda init
conda install -y anaconda-clean
conda update --all -y
EOF_INSTRUCTIONS

sudo chown "$SUDO_USER" run_manually.sh
chmod 755 run_manually.sh
func_print_info_message "Post-install helper written to run_manually.sh"

func_print_info_message "script end $(basename "$0")"
exit 0
