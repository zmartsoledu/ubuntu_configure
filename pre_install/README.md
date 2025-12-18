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

The script prompts for installation parameters (username, locale, timezone, LUKS passphrase, etc.), updates `user-data`/`meta-data`, and regenerates `post_install_instructions.txt` so those values travel with every build.

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

## Next steps

Once the autoinstall finishes, log in as the bootstrap sudo user you configured (default `zmartadmin` with the password you provided), clone or copy the repository, and follow the staged instructions in `post_install/README.md` to build up the rest of the environment.
