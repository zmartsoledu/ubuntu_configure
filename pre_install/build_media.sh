#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_SCRIPT="${SCRIPT_DIR}/configure_autoinstall.sh"
POST_INSTALL_DIR="${SCRIPT_DIR}/../post_install"
DEFAULTS_BASE="${POST_INSTALL_DIR}/defaults.env"
DEFAULTS_OVERRIDE="${POST_INSTALL_DIR}/defaults_override.env"
DEFAULTS_FILE=""

if [ "$EUID" -ne 0 ]; then
    echo "EXIT[ERR]: build_media.sh must be run with sudo/root privileges" >&2
    exit 1
fi

ISO_INPUT=""
OUTPUT_ISO=""
SEED_IMG="seed.img"
FLASH_ONLY=0

usage() {
    cat <<'EOF'
Usage: build_media.sh [--iso /path/to/ubuntu.iso] [--output custom.iso] [--seed seed.img]

Options:
  --iso PATH       Path to the Ubuntu Server ISO (required unless autodownload kicks in).
  --output PATH    Output ISO name (defaults to <input>_autoinstall_<timestamp>.iso).
  --seed PATH      Seed image name (default: seed.img).
  --flash-only     Skip ISO customization and only flash an existing ISO to USB.
  --help           Show this help and exit.
EOF
}

select_defaults_file() {
    if [ -f "$DEFAULTS_OVERRIDE" ]; then
        printf '%s\n' "$DEFAULTS_OVERRIDE"
    elif [ -f "$DEFAULTS_BASE" ]; then
        printf '%s\n' "$DEFAULTS_BASE"
    else
        printf ''
    fi
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
        --flash-only)
            FLASH_ONLY=1
            shift
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

if [ "$FLASH_ONLY" -eq 1 ] && [ -z "$ISO_INPUT" ]; then
    echo "EXIT[ERR]: --flash-only requires --iso /path/to/existing.iso" >&2
    exit 1
fi

DEFAULTS_FILE="$(select_defaults_file)"
if [ -z "$DEFAULTS_FILE" ]; then
    echo "EXIT[ERR]: Could not find ${DEFAULTS_OVERRIDE} or ${DEFAULTS_BASE}. Run configure_autoinstall.sh first." >&2
    exit 1
fi

WORKDIR=$(mktemp -d)
NOCLOUD_TMP=$(mktemp -d)
cleanup() {
    [[ -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
    [[ -d "$NOCLOUD_TMP" ]] && rm -rf "$NOCLOUD_TMP"
}
trap cleanup EXIT

copy_nocloud_sources() {
    local user_data_src="${SCRIPT_DIR}/user-data"
    if [ -f "${SCRIPT_DIR}/user-data-override" ]; then
        user_data_src="${SCRIPT_DIR}/user-data-override"
        echo "[i] Using customized user-data-override"
    else
        echo "[i] Using stock user-data"
    fi

    if [ ! -f "$user_data_src" ]; then
        echo "EXIT[ERR]: user-data source missing. Run configure_autoinstall.sh." >&2
        exit 1
    fi

    cp "$user_data_src" "$NOCLOUD_TMP/user-data"

    local files=(meta-data post_install_instructions.txt)
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
    if [ "$FLASH_ONLY" -eq 0 ]; then
        set_default_output_name
    elif [ -z "$OUTPUT_ISO" ]; then
        OUTPUT_ISO="$ISO_INPUT"
    fi
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

extract_efi_partition() {
    local iso="$1" out="$2"
    local part_info
    if ! part_info=$(python3 - "$iso" <<'PY'
import json
import subprocess
import sys

iso_path = sys.argv[1]
try:
    result = subprocess.run(
        ["sfdisk", "--json", iso_path],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
except subprocess.CalledProcessError as err:
    sys.stderr.write(err.stderr)
    sys.exit(err.returncode or 1)

try:
    data = json.loads(result.stdout)
except Exception as exc:
    sys.stderr.write(f"Failed to parse sfdisk output: {exc}\n")
    sys.exit(1)

sectorsize = data.get("partitiontable", {}).get("sectorsize", 512) or 512
wanted = {
    "c12a7328-f81f-11d2-ba4b-00a0c93ec93b",
    "0xef",
    "ef00",
}
for part in data.get("partitiontable", {}).get("partitions", []):
    part_type = (part.get("type") or "").lower()
    if part_type in wanted or part_type.endswith("c93ec93b"):
        start = part.get("start")
        size = part.get("size")
        if start is not None and size is not None:
            print(start, size, sectorsize)
            sys.exit(0)
sys.exit(1)
PY
    ); then
        echo "EXIT[ERR]: Failed to inspect EFI partition inside ${iso}" >&2
        return 1
    fi
    if [ -z "$part_info" ]; then
        echo "EXIT[ERR]: EFI partition metadata missing for ${iso}" >&2
        return 1
    fi
    local start size sector
    read -r start size sector <<<"$part_info"
    if [ -z "${start:-}" ] || [ -z "${size:-}" ]; then
        echo "EXIT[ERR]: Could not determine EFI partition offsets for ${iso}" >&2
        return 1
    fi
    : "${sector:=512}"
    mkdir -p "$(dirname "$out")"
    dd if="$iso" of="$out" bs="$sector" skip="$start" count="$size" status=none
}

patch_grub() {
    local grub_path="$1"
    python3 - "$grub_path" <<'PY'
from pathlib import Path
import re
import sys

AUTO_TITLE = "Autoinstall Ubuntu Server (default)"
path = Path(sys.argv[1])
text = path.read_text()
if AUTO_TITLE in text:
    sys.exit(0)

pattern_try = re.compile(r"(menuentry\s+(?P<quote>['\"])(?P<title>[^'\"]*?Try or Install[^'\"]*?)(?P=quote).*?\n})", re.S | re.I)
match = pattern_try.search(text)
if not match:
    pattern_any = re.compile(r"(menuentry\s+(?P<quote>['\"])(?P<title>[^'\"]+)(?P=quote).*?\n})", re.S)
    match = pattern_any.search(text)
if not match:
    raise SystemExit('Could not find menuentry to duplicate')

block = match.group(0)
quote = match.group('quote')
orig_title = match.group('title')
auto_block = block.replace(f"{quote}{orig_title}{quote}", f"{quote}{AUTO_TITLE}{quote}", 1)
auto_block = re.sub(r"(linux\s+[^\n]+?)\s+---", r"\1 autoinstall ds=nocloud;s=/cdrom/nocloud/ ---", auto_block, count=1)
start, end = match.span()
text = text[:start] + auto_block + "\n\n" + block + text[end:]

default_pattern = re.compile(r"set default=.*")
if default_pattern.search(text):
    text = default_pattern.sub(f"set default=\"{AUTO_TITLE}\"", text, count=1)
else:
    marker = "set timeout"
    idx = text.find(marker)
    insert = f"set default=\"{AUTO_TITLE}\"\n"
    if idx != -1:
        line_end = text.find("\n", idx)
        if line_end == -1:
            line_end = idx + len(marker)
        text = text[:line_end+1] + insert + text[line_end+1:]
    else:
        text = insert + text

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

    local efi_img="$custom/boot/grub/efi.img"
    if [ ! -f "$efi_img" ]; then
        efi_img=$(find "$custom" -maxdepth 4 -name 'efi.img' -print -quit)
    fi
    if [ -z "$efi_img" ] || [ ! -f "$efi_img" ]; then
        local extracted_efi="$WORKDIR/efi.img"
        if extract_efi_partition "$ISO_INPUT" "$extracted_efi"; then
            efi_img="$extracted_efi"
            echo "[i] Extracted EFI partition for reuse (${efi_img})"
        else
            echo "EXIT[ERR]: Could not locate or extract efi.img inside the ISO" >&2
            exit 1
        fi
    fi

    echo "[+] Building autoinstall ISO ${OUTPUT_ISO}"
    sudo_cmd xorriso -as mkisofs -r \
      -V 'Ubuntu 24.04 Autoinstall' \
      -o "$OUTPUT_ISO" \
      --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
      -partition_offset 16 --mbr-force-bootable \
      -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$efi_img" \
      -appended_part_as_gpt -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
      -c '/boot.catalog' \
      -b '/boot/grub/i386-pc/eltorito.img' -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
      -eltorito-alt-boot -e '--interval:appended_partition_2:::' -no-emul-boot \
      "$custom"
}

detect_usb_devices() {
    mapfile -t USB_CHOICES < <(lsblk -dpno NAME,RM,SIZE,MODEL,TRAN,TYPE -P)
}

unmount_block_device() {
    local dev="$1"
    local entries
    mapfile -t entries < <(lsblk -rno MOUNTPOINT "${dev}" "${dev}"?* 2>/dev/null | awk 'NF')
    if [ ${#entries[@]} -gt 0 ]; then
        echo "[i] Unmounting volumes on ${dev}"
        for mp in "${entries[@]}"; do
            if findmnt -rno TARGET --target "$mp" >/dev/null 2>&1; then
                sudo_cmd umount "$mp" || echo "[WARN] Failed to unmount $mp"
            fi
        done
    fi
}

prompt_usb_target() {
    detect_usb_devices
    declare -a USB_NAMES=()
    if [ "${#USB_CHOICES[@]}" -eq 0 ]; then
        echo "[i] No block devices detected via lsblk. Skipping image write."
        return
    fi

    local idx=1
    printf "\nDetected disks (USB/removable flagged):"
    for entry in "${USB_CHOICES[@]}"; do
        eval "$entry"
        if [ "$TYPE" != "disk" ]; then
            continue
        fi
        if [ "$TRAN" != "usb" ] && [ "$RM" != "1" ]; then
            continue
        fi
        local tags=()
        [ "$TRAN" = "usb" ] && tags+=("USB")
        [ "$RM" = "1" ] && tags+=("removable")
        local tag=""
        if [ "${#tags[@]}" -gt 0 ]; then
            tag=" [${tags[*]}]"
        fi
        printf "  %d) %s (%s, %s)%s\n" "$idx" "$NAME" "$SIZE" "${MODEL:-Unknown}" "$tag"
        USB_NAMES[$idx]="$NAME"
        idx=$((idx+1))
    done

    if [ $idx -eq 1 ]; then
        echo "[i] No USB/removable disks found. Skipping image write."
        return
    fi

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
    unmount_block_device "$target"
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
    require_cmd lsblk
    require_cmd findmnt

    if [ "$FLASH_ONLY" -eq 1 ]; then
        require_cmd dd
        require_cmd partprobe
        ensure_iso_ready
        OUTPUT_ISO="$ISO_INPUT"
        echo "[i] Flash-only mode: skipping ISO customization."
        prompt_usb_target
        echo ""
        echo "[Done] Flashed image: $OUTPUT_ISO"
        echo "Defaults file: $DEFAULTS_FILE"
        return
    fi

    require_cmd cloud-localds
    require_cmd xorriso
    require_cmd sfdisk
    require_cmd rsync
    require_cmd python3

    copy_nocloud_sources
    ensure_iso_ready
    build_seed_image
    build_custom_iso
    prompt_usb_target

    printf "\n[Done] Outputs:"
    echo "  ISO : $OUTPUT_ISO"
    echo "  Seed: $SEED_IMG"
    echo "  Defaults file: $DEFAULTS_FILE"
    printf "\nReview the installer values in: $DEFAULTS_FILE"
}

main "$@"
