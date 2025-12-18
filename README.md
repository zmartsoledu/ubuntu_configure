# ubuntu_configure

This repository automates both halves of building a reproducible Ubuntu 24.04 workstation:

- `pre_install/` turns the stock Ubuntu Server ISO into an unattended, LUKS-encrypted autoinstall image (or cloud-init seed) with safe defaults.
- `post_install/` layers the rest of the system — from a hardened server baseline all the way to a desktop/laptop with developer tooling — using staged shell scripts.

> ! These scripts repartition target disks and assume fresh installs. Back up important data before proceeding, and only run them on machines you intend to wipe.

## Workflow overview

1. **Create installation media (pre_install/README.md).**
   - Run `pre_install/configure_autoinstall.sh` to confirm or override the bootstrap user, password, hostname, LUKS passphrase, etc.
   - Download the Ubuntu 24.04 Server ISO.
   - Copy in the provided `user-data` / `meta-data` files (updated by the helper).
   - Patch GRUB to add the "Autoinstall" boot option while keeping the manual installer as a fallback.
   - Repack and write the ISO to USB, or generate a `seed.img` for VM testing with a vanilla ISO.
2. **Run staged post-install scripts (post_install/README.md).**
   - Start from the freshly installed encrypted server.
   - Execute the scripts in numerical order to add users, packages, graphics drivers, GNOME, optional apps, laptop tweaks, snap removal, and LUKS auto-unlock.

The stages are intentionally modular, so you can stop after the server baseline or continue to a full desktop experience. See the per-folder README files for detailed instructions and prerequisites.

**Tested target:** Ubuntu 24.04 LTS

Additional background lives in the [project wiki](https://github.com/zmartsoledu/ubuntu_configure/wiki). Everything here is released under the [MIT license](LICENSE).
