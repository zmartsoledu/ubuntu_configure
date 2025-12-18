# Post-install automation (layered system build)

These scripts assume you have completed the unattended Ubuntu 24.04 installation defined in `pre_install/`. Copy this folder onto the freshly installed machine (e.g., via USB or git) and run the scripts in order. Each stage adds a discrete layer so you can stop once your requirements are met.

> Run every script with `sudo ./script_name.sh`. Many actions reboot the system; follow the prompts.

## Stage 1 – Secure server baseline

1. `1_a_user_psswd_mods.sh`
   - Enforce `/bin/sh -> bash`, set timezone, and configure the real admin user.
   - Change hostname (default `zmart-u24`) and replace the default LUKS passphrase (`zmart-default-luks`).
   - Optionally remove the bootstrap `zmartadmin` account and launch `luks_autounlock.sh` for USB/YubiKey unlock.
2. *(After reboot, log in as the new admin and run `~/first_boot.sh` if it was generated.)*
3. `1_b_upgrade_after_first_boot.sh`
   - Full system upgrade + firmware refresh.
4. `1_c_server_extras.sh`
   - Installs foundational tooling: build-essential, libvirt/KVM, Docker (with compose plugin), Azure/Vagrant helpers, CLI utilities, etc.

## Stage 2 – Graphics preparation

- `2_pre_graph.sh`
  - Detects Intel Arc / NVIDIA / AMD GPUs and invokes `graphics_card.sh` accordingly.
  - Handles firmware, kernel modules, and driver repos.

## Stage 3 – Desktop, networking, and productivity

1. `gnome_desktop.sh`
   - Installs the minimal Ubuntu desktop stack without snaps.
2. `3_post_graph.sh`
   - Switches to NetworkManager, configures Flatpak, installs fonts, PowerShell, VS Code repo, etc.
3. `general.sh` & `docker.sh`
   - Already covered for server usage, but rerun if you skipped them earlier and now need desktop conveniences.

## Stage 4 – Optional desktop applications

- `4_graph_optionals.sh`
  - Adds browsers, communication tools, flatpak apps, media utilities, etc. Edit the script to tailor the list before executing.

## Stage 5 – Snap removal

- `5_snap_removal.sh`
  - Purges snapd only after flatpak/native replacements exist, places apt holds, and cleans lingering snap mounts. Reboot afterward.

## Stage 6 – Laptop extras

- `6_laptop_extras.sh`
  - Enables Wi-Fi/Bluetooth firmware, TLP power tuning, suspend fixes, brightness controls, and other mobile-focused tweaks.

## Optional hardening & convenience scripts

- `check_sshd_status.sh` – Confirms SSH is disabled once setup is complete.
- `bash_aliases`, `groups.sh`, `nm_dns.sh`, etc. – Small helpers you can source or run as needed.
- `luks_autounlock.sh` – Re-runnable helper if you skipped USB/YubiKey auto-decrypt earlier.

## Recommended verification

After each stage, validate the state before continuing:

```bash
# Stage 1
systemctl status ssh
sudo docker compose version

# Stage 3
nmcli device
flatpak list

# Stage 5
snap list 2>&1 | grep "not found"
```

For more context on what each script installs, open it in an editor or consult the project wiki. Feel free to comment out sections you do not need before executing.
