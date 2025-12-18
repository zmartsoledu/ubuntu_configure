#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_SCRIPT="${SCRIPT_DIR}/configure_autoinstall.sh"
DEFAULTS_FILE="${SCRIPT_DIR}/autoinstall.defaults"

if [ "$EUID" -ne 0 ]; then
    echo "EXIT[ERR]: build_media.sh must be run with sudo/root privileges" >&2
    exit 1
fi

if [ ! -f "$DEFAULTS_FILE" ]; then
    echo "EXIT[ERR]: ${DEFAULTS_FILE} missing. Run configure_autoinstall.sh first." >&2
    exit 1
fi

ISO_INPUT=""
OUTPUT_ISO=""
SEED_IMG="seed.img"

usage() {
    cat <<'EOF'
Usage: build_media.sh [--iso /path/to/ubuntu.iso] [--output custom.iso] [--seed seed.img]

Options:
  --iso PATH       Path to the Ubuntu Server ISO (required).
  --output PATH    Output ISO name (defaults to <input>_autoinstall_<timestamp>.iso).
  --seed PATH      Seed image name (default: seed.img).
  --help           Show this help and exit.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)
            ISO_INPUT="$2"
            shift 2
            ;;
        --output)
            OUTPUT_ISO="$2"
            shift 2
            ;;
        --seed)
            SEED_IMG="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "EXIT[ERR]: Unknown option $1" >&2
            usage
            exit 1
            ;;
    esac
done
WORKDIR=$(mktemp -d)
NOCLOUD_TMP=$(mktemp -d)
cleanup() {
    [[ -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
    [[ -d "$NOCLOUD_TMP" ]] && rm -rf "$NOCLOUD_TMP"
}
trap cleanup EXIT

copy_nocloud_sources() {
    local files=(user-data meta-data post_install_instructions.txt)
    for f in "${files[@]}"; do
        if [ ! -f "${SCRIPT_DIR}/${f}" ]; then
            echo "EXIT[ERR]: ${f} missing. Run configure_autoinstall.sh." >&2
            exit 1
        fi
        cp "${SCRIPT_DIR}/${f}" "$NOCLOUD_TMP/"
    done
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "EXIT[ERR]: Missing dependency: $1" >&2
        exit 1
    fi
}

download_latest_ubuntu_iso() {
    local release="$1"
    local flavour="$2"
    local pattern description
    local escaped_release="${release//./\\.}"
    local base_url="https://releases.ubuntu.com/${release}/"
    local checksum_file
    checksum_file=$(mktemp)
    echo "[i] Fetching SHA256SUMS from ${base_url}"
    if ! curl -fsSL "${base_url}SHA256SUMS" -o "$checksum_file"; then
        echo "EXIT[ERR]: Failed to download SHA256SUMS from ${base_url}" >&2
        rm -f "$checksum_file"
        exit 1
    fi
    case "$flavour" in
        server)
            pattern="ubuntu-${escaped_release}[^\" ]*-live-server-amd64\\.iso"
            description="Ubuntu ${release} live server"
            ;;
        desktop)
            pattern="ubuntu-${escaped_release}[^\" ]*-desktop-amd64\\.iso"
            description="Ubuntu ${release} desktop"
            ;;
        *)
            echo "EXIT[ERR]: Unknown flavour $flavour" >&2
            rm -f "$checksum_file"
            exit 1
            ;;
    esac

    echo "[+] Resolving latest ${description} ISO..."
    local iso_name
    iso_name=$(curl -fsSL "$base_url" | grep -oE "$pattern" | sort -Vr | head -n1 || true)
    if [ -z "$iso_name" ]; then
        echo "EXIT[ERR]: Could not determine latest ${description} ISO" >&2
        rm -f "$checksum_file"
        exit 1
    fi

    local dest="$PWD/$iso_name"
    local expected_hash
    expected_hash=$(awk -v iso="$iso_name" '{fname=$2; gsub("\\*", "", fname); if (fname==iso) {print $1; exit}}' "$checksum_file" || true)
    if [ -z "$expected_hash" ]; then
        echo "EXIT[ERR]: Could not find checksum entry for ${iso_name}" >&2
        rm -f "$checksum_file"
        exit 1
    fi

    local have_valid_iso="false"
    if [ -f "$dest" ]; then
        echo "[i] Verifying existing $dest checksum"
        local current
        current=$(sha256sum "$dest" | awk '{print $1}')
        if [ "$current" = "$expected_hash" ]; then
            echo "[i] Using existing $dest (checksum verified)"
            have_valid_iso="true"
        else
            echo "[WARN] Existing $dest checksum mismatch. Re-downloading."
            rm -f "$dest"
        fi
    fi

    if [ "$have_valid_iso" != "true" ]; then
        echo "[+] Downloading $iso_name"
        if ! wget -O "$dest" "${base_url}${iso_name}"; then
            echo "EXIT[ERR]: Failed to download ${description} ISO" >&2
            rm -f "$dest"
            rm -f "$checksum_file"
            exit 1
        fi
        echo "[i] Calculating checksum for $dest"
        local current
        current=$(sha256sum "$dest" | awk '{print $1}')
        if [ "$current" != "$expected_hash" ]; then
            echo "EXIT[ERR]: Downloaded ${iso_name} but checksum verification failed" >&2
            rm -f "$dest"
            rm -f "$checksum_file"
            exit 1
        fi
    fi
    ISO_INPUT="$dest"
    rm -f "$checksum_file"
}

set_default_output_name() {
    if [ -n "$OUTPUT_ISO" ]; then
        return
    fi
    local base="$(basename "$ISO_INPUT")"
    local stem="${base%.*}"
    local ts="$(date -u +%y_%m_%d__%H_%M_%S)"
    OUTPUT_ISO="${stem}_autoinstall_${ts}.iso"
}

choose_iso_source() {
    echo "No ISO path provided. Choose a source:"
    echo "  1) Download latest Ubuntu 24.04 live server (amd64)"
    echo "  2) Download latest Ubuntu 24.04 desktop (amd64)"
    echo "  3) Enter a custom ISO path"
    echo "  q) Quit"
    while true; do
        read -r -p "Selection [q]: " choice || true
        case "${choice:-q}" in
            1)
                download_latest_ubuntu_iso "24.04" server
                break
            ;;
            2)
                download_latest_ubuntu_iso "24.04" desktop
                break
            ;;
            3)
                read -r -p "Enter ISO path: " ISO_INPUT
                if [ -n "$ISO_INPUT" ]; then
                    break
                fi
            ;;
            q|Q|"")
                echo "EXIT[ERR]: ISO selection canceled." >&2
                exit 1
            ;;
            *)
                echo "Invalid choice."
            ;;
        esac
    done
}

ensure_iso_ready() {
    if [ -z "$ISO_INPUT" ]; then
        choose_iso_source
    fi
    if [ -z "$ISO_INPUT" ]; then
        echo "EXIT[ERR]: ISO path not provided." >&2
        exit 1
    fi
    if [ ! -f "$ISO_INPUT" ]; then
        echo "EXIT[ERR]: ISO not found at $ISO_INPUT" >&2
        exit 1
    fi
    ISO_INPUT="$(readlink -f "$ISO_INPUT")"
    set_default_output_name
}

sudo_cmd() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

build_seed_image() {
    echo "[+] Generating seed image ${SEED_IMG}"
    cloud-localds "$SEED_IMG" "$NOCLOUD_TMP/user-data" "$NOCLOUD_TMP/meta-data"
}

patch_grub() {
    local grub_path="$1"
    python3 - "$grub_path" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text()
match = re.search(r"(menuentry 'Try or Install Ubuntu Server'.*?\n})", text, re.S)
if not match:
    raise SystemExit('Could not find default menuentry to duplicate')
block = match.group(1)
auto_block = block.replace('Try or Install Ubuntu Server', 'Autoinstall Ubuntu Server (default)', 1)
auto_block = re.sub(r"(linux\\s+[^\n]+?)\\s+---", r"\\1 autoinstall ds=nocloud;s=/cdrom/nocloud/ ---", auto_block)
text = text.replace(block, auto_block + "\n\n" + block, 1)
path.write_text(text)
PY
}

build_custom_iso() {
    local mnt="$WORKDIR/mnt" custom="$WORKDIR/custom"
    mkdir -p "$mnt" "$custom"
    sudo_cmd mount -o loop "$ISO_INPUT" "$mnt"
    cp -a "$mnt/." "$custom/"
    sudo_cmd umount "$mnt"

    local nocloud_dest="$custom/nocloud"
    mkdir -p "$nocloud_dest"
    rsync -a "$NOCLOUD_TMP/" "$nocloud_dest/"

    patch_grub "$custom/boot/grub/grub.cfg"

    echo "[+] Building autoinstall ISO ${OUTPUT_ISO}"
    sudo_cmd xorriso -as mkisofs -r \
      -V 'Ubuntu 24.04 Autoinstall' \
      -o "$OUTPUT_ISO" \
      --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
      -partition_offset 16 --mbr-force-bootable \
      -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$custom/boot/grub/efi.img" \
      -appended_part_as_gpt -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
      -c '/boot.catalog' \
      -b '/boot/grub/i386-pc/eltorito.img' -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
      -eltorito-alt-boot -e '--interval:appended_partition_2:::' -no-emul-boot \
      "$custom"
}

detect_usb_devices() {
    mapfile -t USB_CHOICES < <(lsblk -dpno NAME,RM,SIZE,MODEL -P | awk '$0 ~ /RM="1"/ {print $0}')
}

prompt_usb_target() {
    detect_usb_devices
    declare -a USB_NAMES=()
    if [ "${#USB_CHOICES[@]}" -eq 0 ]; then
        echo "[i] No removable USB devices detected. Skipping image write."
        return
    fi

    echo "\nDetected removable devices:"
    local idx=1
    for entry in "${USB_CHOICES[@]}"; do
        eval "$entry"
        printf "  %d) %s (%s, %s)\n" "$idx" "$NAME" "$SIZE" "${MODEL:-Unknown}"
        USB_NAMES[$idx]="$NAME"
        idx=$((idx+1))
    done

    read -t 10 -r -p "Select device number to flash ${OUTPUT_ISO} [skip]: " choice || true
    echo ""
    if [ -z "${choice:-}" ]; then
      echo "[i] Skipping USB write. Example command: sudo dd if=${OUTPUT_ISO} of=/dev/sdX bs=4M status=progress oflag=sync conv=fsync"
      return
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ -z "${USB_NAMES[$choice]:-}" ]; then
        echo "[WARN] Invalid selection. Skipping USB write."
        return
    fi
    local target="${USB_NAMES[$choice]}"
    read -r -p "Type 'yes' to confirm writing ${OUTPUT_ISO} to ${target}: " confirm
    if [ "$confirm" != "yes" ]; then
        echo "[i] USB write canceled."
        return
    fi
    echo "[+] Writing ${OUTPUT_ISO} to ${target}"
    sudo_cmd dd if="$OUTPUT_ISO" of="$target" bs=4M status=progress oflag=sync conv=fsync
    sudo_cmd partprobe "$target" || true
}

main() {
    require_cmd cloud-localds
    require_cmd xorriso
    require_cmd lsblk
    require_cmd rsync
    require_cmd python3

    copy_nocloud_sources
    ensure_iso_ready
    build_seed_image
    build_custom_iso
    prompt_usb_target

    echo "\n[Done] Outputs:"
    echo "  ISO : $OUTPUT_ISO"
    echo "  Seed: $SEED_IMG"
}

main "$@"
