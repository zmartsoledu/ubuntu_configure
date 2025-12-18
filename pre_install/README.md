# Pre-install automation (autoinstall media)

This folder contains the `user-data` and `meta-data` files that turn the stock Ubuntu 24.04 Server ISO into a fully unattended, LUKS-encrypted installer. Use these instructions to build either a custom USB image or a small `seed.img` for VM testing.

## Requirements

- Ubuntu 24.04 (or similar) ISO downloaded locally (e.g., `ubuntu-24.04-live-server-amd64.iso`).
- A Linux workstation with `curl`, `xorriso`, `grub-pc-bin`, `isolinux`, and `p7zip-full` (if repacking on Debian/Ubuntu: `sudo apt install xorriso grub-pc-bin isolinux p7zip-full`).
- A USB drive (≥ 4 GB) or a VM that can attach ISO/IMG files.

## Files

| File | Purpose |
|------|---------|
| `user-data` | Cloud-init autoinstall specification |
| `meta-data` | Required placeholder metadata for the NoCloud datasource |

## Configure autoinstall defaults

Run the helper to review or override the bootstrap values before repacking the ISO:

```bash
cd pre_install
./configure_autoinstall.sh
```

The script prompts for installation parameters if you are not happy with the default. 

## Build a custom autoinstall ISO / USB

```bash
ISO=ubuntu-24.04-live-server-amd64.iso
WORKDIR=/tmp/ubuntu-autoinstall
sudo rm -rf "$WORKDIR" && mkdir -p "$WORKDIR"/iso
sudo mount -o loop "$ISO" "$WORKDIR"/iso
cp -rT "$WORKDIR"/iso "$WORKDIR"/custom
sudo umount "$WORKDIR"/iso

# Copy NoCloud data
mkdir -p "$WORKDIR"/custom/nocloud
cp pre_install/user-data pre_install/meta-data pre_install/post_install_instructions.txt "$WORKDIR"/custom/nocloud/

# Duplicate the default entry so GRUB boots autoinstall by default but keeps manual fallback
sudo python3 - "$WORKDIR/custom/boot/grub/grub.cfg" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text()
match = re.search(r"(menuentry 'Try or Install Ubuntu Server'.*?\n})", text, re.S)
if not match:
    raise SystemExit('Could not find menu entry to duplicate')
block = match.group(1)
auto = block.replace('Try or Install Ubuntu Server', 'Autoinstall Ubuntu Server (default)', 1)
auto = re.sub(r"(linux\\s+[^\n]+?)\\s+---", r"\\1 autoinstall ds=nocloud;s=/cdrom/nocloud/ ---", auto)
text = text.replace(block, auto + "\n\n" + block, 1)
path.write_text(text)
PY

# Repack ISO
target_iso=ubuntu-24.04-autoinstall.iso
sudo xorriso -as mkisofs -r \
  -V 'Ubuntu 24.04 Autoinstall' \
  -o "$target_iso" \
  --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
  -partition_offset 16 --mbr-force-bootable \
  -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$WORKDIR"/custom/boot/grub/efi.img \
  -appended_part_as_gpt -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
  -c '/boot.catalog' \
  -b '/boot/grub/i386-pc/eltorito.img' -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
  -eltorito-alt-boot -e '--interval:appended_partition_2:::' -no-emul-boot \
  "$WORKDIR"/custom

# Write to USB (double-check target device!)
sudo dd if="$target_iso" of=/dev/sdX bs=4M status=progress oflag=sync
```

At boot you will see two entries: **Autoinstall Ubuntu Server (default)** and the original interactive installer as a fallback.

## Quick VM testing via cloud-init seed

Instead of rebuilding the ISO, you can attach a vanilla Ubuntu Server ISO and a seed image providing the same data:

```bash
cloud-localds seed.img pre_install/user-data pre_install/meta-data
```

Attach `seed.img` as a secondary disk (VirtIO/SATA) and add the kernel parameter `autoinstall ds=nocloud;s=/dev/sdX` (or use the GRUB edit prompt) when booting the stock ISO.

## Next steps

Once the autoinstall finishes, log in as `zmartadmin` / `ubuntu`, copy the `post_install/` folder, and follow the staged instructions in `post_install/README.md` to build up the rest of the environment.
