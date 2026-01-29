#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_DATA="${SCRIPT_DIR}/user-data"
META_DATA="${SCRIPT_DIR}/meta-data"
POST_INSTALL_DIR="${SCRIPT_DIR}/../post_install"
DEFAULTS_FILE_BASE="${POST_INSTALL_DIR}/defaults.env"
DEFAULTS_OVERRIDE_FILE="${POST_INSTALL_DIR}/defaults_override.env"
USER_DATA_OVERRIDE="${SCRIPT_DIR}/user-data-override"
INSTRUCTIONS_TEMPLATE="${SCRIPT_DIR}/post_install_instructions.template"
INSTRUCTIONS_OUTPUT="${SCRIPT_DIR}/post_install_instructions.txt"

if [ ! -f "$USER_DATA" ]; then
    echo "EXIT[ERR]: user-data not found in ${SCRIPT_DIR}" >&2
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "EXIT[ERR]: openssl is required to hash passwords" >&2
    exit 1
fi

if [ ! -f "$DEFAULTS_FILE_BASE" ]; then
    echo "EXIT[ERR]: ${DEFAULTS_FILE_BASE} is missing. Restore it from version control." >&2
    exit 1
fi

# Always source the tracked defaults; overrides merely record past answers.
# shellcheck disable=SC1090
source "$DEFAULTS_FILE_BASE"

prompt_value() {
    local prompt default var
    prompt="$1"
    default="$2"
    read -r -p "${prompt} [${default}]: " var || true
    if [ -z "$var" ]; then
        echo "$default"
    else
        echo "$var"
    fi
}

read_secret() {
    local prompt default var
    prompt="$1"
    default="$2"
    read -rs -p "${prompt} [${default}]: " var || true
    printf '\n'
    if [ -z "$var" ]; then
        printf '%s\n' "$default"
    else
        printf '%s\n' "$var"
    fi
}

trim_secret() {
    printf '%s' "$1" | tr -d '\r\n'
}

ADMIN_HOSTNAME=$(prompt_value "System hostname" "$DEFAULT_HOSTNAME")
ADMIN_USER=$(prompt_value "Sudo username" "$DEFAULT_SUDO_USER")
ADMIN_PASSWORD=$(read_secret "Sudo password" "$DEFAULT_SUDO_PASSWORD")
printf '\n'
LUKS_PASSPHRASE=$(read_secret "LUKS passphrase" "$DEFAULT_LUKS_PASSPHRASE")
printf '\n'
ADMIN_PASSWORD=$(trim_secret "$ADMIN_PASSWORD")
LUKS_PASSPHRASE=$(trim_secret "$LUKS_PASSPHRASE")
SWAP_SIZE_MB=$(prompt_value "Swap size in MB (0 disables swap)" "$DEFAULT_SWAP_SIZE_MB")
LOCALE_VALUE=$(prompt_value "System locale" "$DEFAULT_LOCALE")
KB_LAYOUT=$(prompt_value "Keyboard layout" "$DEFAULT_KB_LAYOUT")
KB_VARIANT=$(prompt_value "Keyboard variant (empty for none)" "$DEFAULT_KB_VARIANT")
TIMEZONE_VALUE=$(prompt_value "Timezone (e.g. Europe/London)" "$DEFAULT_TIMEZONE")
INSTANCE_ID=$(prompt_value "Instance ID (meta-data)" "$DEFAULT_INSTANCE_ID")
LOCAL_HOSTNAME=$(prompt_value "Local hostname (meta-data)" "$DEFAULT_LOCAL_HOSTNAME")

PASSWORD_HASH=$(printf '%s' "$ADMIN_PASSWORD" | openssl passwd -6 -stdin | tr -d '\r\n')

escape_sed() {
    printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

HOST_ESC=$(escape_sed "$ADMIN_HOSTNAME")
USER_ESC=$(escape_sed "$ADMIN_USER")
PASS_ESC=$(escape_sed "$PASSWORD_HASH")
LUKS_ESC=$(escape_sed "$LUKS_PASSPHRASE")
SWAP_ESC=$(escape_sed "$SWAP_SIZE_MB")
LOCALE_ESC=$(escape_sed "$LOCALE_VALUE")
KB_LAYOUT_ESC=$(escape_sed "$KB_LAYOUT")
KB_VARIANT_ESC=$(escape_sed "$KB_VARIANT")

VARIANT_YAML="$KB_VARIANT"
if [ -z "$VARIANT_YAML" ]; then
    VARIANT_YAML="''"
fi
VARIANT_YAML_ESC=$(escape_sed "$VARIANT_YAML")

cp "$USER_DATA" "$USER_DATA_OVERRIDE"
TARGET_USER_DATA="$USER_DATA_OVERRIDE"

sed -i "s/^    hostname: .*/    hostname: ${HOST_ESC}/" "$TARGET_USER_DATA"
sed -i "s/^  locale: .*/  locale: ${LOCALE_ESC}/" "$TARGET_USER_DATA"
sed -i "s/^    layout: .*/    layout: ${KB_LAYOUT_ESC}/" "$TARGET_USER_DATA"
sed -i "s/^    variant: .*/    variant: ${VARIANT_YAML_ESC}/" "$TARGET_USER_DATA"
sed -i "s/^    username: .*/    username: ${USER_ESC}/" "$TARGET_USER_DATA"
sed -i "s|^    password: \".*\"|    password: \"${PASS_ESC}\"|" "$TARGET_USER_DATA"
sed -i "s|^      password: \".*\"  # Default LUKS passphrase.*|      password: \"${LUKS_ESC}\"  # Default LUKS passphrase, change in post-install|" "$TARGET_USER_DATA"
sed -i "s/^      size: .*/      size: ${SWAP_ESC}/" "$TARGET_USER_DATA"
sed -i "s|^    timezone: .*|    timezone: ${TIMEZONE_VALUE}|" "$TARGET_USER_DATA"
sed -i "s|/usr/share/zoneinfo/.\+ /etc/localtime|/usr/share/zoneinfo/${TIMEZONE_VALUE} /etc/localtime|" "$TARGET_USER_DATA"

python3 - "$TARGET_USER_DATA" "$ADMIN_PASSWORD" <<'PY'
import sys
path, pwd = sys.argv[1:3]
with open(path, 'r', encoding='utf-8') as fh:
    lines = fh.readlines()
comment = f"    # Plaintext sudo password: {pwd}\n"
prefix = "    password:"
for idx, line in enumerate(lines):
    if line.startswith(prefix):
        if idx > 0 and lines[idx-1].startswith("    # Plaintext sudo password:"):
            lines[idx-1] = comment
        else:
            lines.insert(idx, comment)
        break
with open(path, 'w', encoding='utf-8') as fh:
    fh.writelines(lines)
PY

cat > "$META_DATA" <<EOF
instance-id: ${INSTANCE_ID}
local-hostname: ${LOCAL_HOSTNAME}
EOF

{
    printf '# SUDO_PASSWORD_PLAINTEXT=%s\n' "$ADMIN_PASSWORD"
    printf '# LUKS_PASSPHRASE_PLAINTEXT=%s\n' "$LUKS_PASSPHRASE"
    cat <<EOF
DEFAULT_SUDO_USER="${ADMIN_USER}"
DEFAULT_SUDO_PASSWORD="${ADMIN_PASSWORD}"
DEFAULT_HOSTNAME="${ADMIN_HOSTNAME}"
DEFAULT_LUKS_PASSPHRASE="${LUKS_PASSPHRASE}"
DEFAULT_SWAP_SIZE_MB="${SWAP_SIZE_MB}"
DEFAULT_INSTANCE_ID="${INSTANCE_ID}"
DEFAULT_LOCAL_HOSTNAME="${LOCAL_HOSTNAME}"
DEFAULT_LOCALE="${LOCALE_VALUE}"
DEFAULT_KB_LAYOUT="${KB_LAYOUT}"
DEFAULT_KB_VARIANT="${KB_VARIANT}"
DEFAULT_TIMEZONE="${TIMEZONE_VALUE}"
EOF
} > "$DEFAULTS_OVERRIDE_FILE"

echo "[i] Stored installer answers in ${DEFAULTS_OVERRIDE_FILE}"

if [ -f "$INSTRUCTIONS_TEMPLATE" ]; then
    SUDO_USER_ESC=$(escape_sed "$ADMIN_USER")
    sed "s/__SUDO_USER__/${SUDO_USER_ESC}/g" "$INSTRUCTIONS_TEMPLATE" > "$INSTRUCTIONS_OUTPUT"
fi

echo "Updated user-data and meta-data with the selected values."
