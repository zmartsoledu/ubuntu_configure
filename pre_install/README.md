# Pre-install automation (autoinstall media)

This folder contains the `user-data` and `meta-data` files that turn the stock Ubuntu 24.04 Server ISO into a fully unattended, LUKS-encrypted installer. Use these instructions to build either a custom USB image or a small `seed.img` for VM testing.

## Requirements

- Ubuntu 24.04 (or similar) ISO downloaded locally (e.g., `ubuntu-24.04-live-server-amd64.iso`).
  - Latest server ISO:
    ```bash
    SERVER_ISO=$(curl -s https://releases.ubuntu.com/24.04/ \
      | grep -o 'ubuntu-24\.04[^" ]*-live-server-amd64\.iso' \
      | sort -Vr | head -n1)
    wget "https://releases.ubuntu.com/24.04/${SERVER_ISO}"
    ```
  - Latest desktop ISO:
    ```bash
    DESKTOP_ISO=$(curl -s https://releases.ubuntu.com/24.04/ \
      | grep -o 'ubuntu-24\.04[^" ]*-desktop-amd64\.iso' \
      | sort -Vr | head -n1)
    wget "https://releases.ubuntu.com/24.04/${DESKTOP_ISO}"
    ```
- A Linux workstation with `xorriso`, `cloud-image-utils` (for `cloud-localds`), `rsync`, `python3`, and `lsblk` (usually from `util-linux`).
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

The script prompts for installation parameters (username, locale, timezone, LUKS passphrase, etc.), updates `user-data`/`meta-data`, and regenerates `post_install_instructions.txt` so those values travel with every build. Your answers are written back into `post_install/defaults.env`, which now serves as the single source of truth for both the installer customization and the Stage 1 hardening script.

## Build media with one command

```bash
cd pre_install
./build_media.sh --iso /path/to/ubuntu-24.04-live-server-amd64.iso
```

- Run it with `sudo` (the script now validates root access up front).
- Optional flags: `--output custom.iso` and `--seed custom_seed.img` (defaults are timestamped ISO + `seed.img`).
- Produces `seed.img` plus a timestamped ISO named after the source image (e.g., `ubuntu-24.04-live-server-amd64_autoinstall_25_01_05__14_32_10.iso`).
- Automatically downloads the latest Ubuntu 24.04 server/desktop ISO on demand and verifies the SHA256 checksum (reusing the file if it already matches).
- Copies that payload into the ISO (`/cdrom/nocloud/…`) and onto the installed server as `/root/ubuntu_configure_next_steps.txt`, so the git clone instructions are already in place after first boot.
- Detects removable USB drives and waits up to 10 seconds for a selection; press Enter (or let it time out) to skip flashing. When skipped, the script prints an example `dd` command.
- Uses `sudo` only for mount/umount and the optional USB write.

At boot you will see two entries: **Autoinstall Ubuntu Server (default)** and the original interactive installer as a fallback. For VM testing, pair the generated `seed.img` with the stock ISO and boot with `autoinstall ds=nocloud;s=/dev/sdX`; the payload matches the ISO exactly, so behavior stays consistent.

## Test quickly with QEMU/KVM (VirtualBox-free workflow)

Most laptops refuse to let nested VirtualBox switch into VMX root mode when they’re already running under KVM or Hyper-V. The commands below let you exercise both the self-contained autoinstall ISO and the stock ISO + `seed.img` combo without touching VirtualBox.

1. Create a disposable VM disk:
   ```bash
   qemu-img create -f qcow2 ~/vm-disks/ubuntu_autoinstall.qcow2 40G
   ```
2. **Use the custom ISO only** (NoCloud payload baked in by `build_media.sh`):
   ```bash
   qemu-system-x86_64 \
     -enable-kvm -machine q35,accel=kvm \
     -cpu host -smp 4 -m 8G \
     -drive file=/path/to/ubuntu-24.04-live-server_autoinstall.iso,media=cdrom,if=virtio \
     -drive file=~/vm-disks/ubuntu_autoinstall.qcow2,if=virtio \
     -boot order=d
   ```
   This boots straight into the “Autoinstall Ubuntu Server (default)” GRUB entry and runs unattended just like bare metal.
3. **Test the `seed.img` with a stock ISO** (useful if you want to keep Canonical’s ISO untouched):
   ```bash
   qemu-system-x86_64 \
     -enable-kvm -machine q35,accel=kvm \
     -cpu host -smp 4 -m 8G \
     -drive file=/path/to/ubuntu-24.04-live-server-amd64.iso,media=cdrom,if=virtio \
     -drive file=~/vm-disks/ubuntu_autoinstall.qcow2,if=virtio \
     -drive file=/path/to/seed.img,format=raw,if=virtio \
     -boot order=d
   ```
   When the GRUB menu appears, highlight *“Try or Install Ubuntu Server”*, press **`e`**, and append the following to the kernel line (right after `quiet`):
   ```
   autoinstall ds=nocloud\;s=/dev/vdb
   ```
   Press **Ctrl+X** or **F10** to boot. `/dev/vdb` is the virtio device that QEMU presents for `seed.img`; adjust the device path if you change the interface type.

You can wrap either invocation with `virt-install` or `aqemu` if you want a GUI, but the raw commands above keep everything reproducible and CI-friendly.

## Next steps

Once the autoinstall finishes, log in as the bootstrap sudo user you configured (default `zmartadmin` with the password you provided), clone or copy the repository, and follow the staged instructions in `post_install/README.md` to build up the rest of the environment.
