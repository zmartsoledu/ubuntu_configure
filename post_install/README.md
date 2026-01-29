# Post-install automation (layered system build)

These scripts assume you have completed the unattended Ubuntu 24.04 installation defined in `pre_install/`. Copy this folder onto the freshly installed machine (e.g., via USB or git) and run the scripts in order. Each stage adds a discrete layer so you can stop once your requirements are met.

> Run every script with `sudo ./script_name.sh`. Many actions reboot the system; follow the prompts.

## Stage 1 – Secure server baseline

1. `1_a_user_psswd_mods.sh`
   - Enforce `/bin/sh -> bash`, set timezone, and configure the real admin user.
   - Auto-detects the primary sudoer (first UID ≥ 1000) and the active hostname, only reading the stored LUKS passphrase/user defaults from `post_install/defaults_override.env` (or `defaults.env` if no override exists) so you no longer have to babysit duplicate `DEFAULT_*` values.
   - Lets you create or reuse a sudoer, immediately reset that account’s password, rename the host, rotate the LUKS passphrase, optionally remove the bootstrap account (deleting it outright when possible or writing `remove_bootstrap_user.sh` next to the scripts so Stage 1_b—or you manually—can finish the job), and launch `luks_autounlock.sh` for USB/YubiKey unlock.
2. *(After reboot, log in as the new admin; any deferred bootstrap-user removal will be handled automatically when you run 1_b.)*
3. `1_b_upgrade_after_first_boot.sh`
   - Runs `remove_bootstrap_user.sh` automatically if it exists, then performs the full system upgrade + firmware refresh.
   - Configures NetworkManager/netplan early via `netplan_nm.sh` (backups original configs with _ suffix for easy recovery).
4. `1_c_snap_cleanup.sh`
   - Stops every snapd unit/socket, backs up `snap list`, purges each snap (core snaps included), removes snapd/flatpak packages, pins them at `Pin-Priority: -1`, cleans all snap/flatpak directories, deletes the PATH hook, and reloads systemd units so nothing snap-related lingers.
5. `1_d_server_extras.sh`
   - Installs foundational tooling plus GitHub Copilot CLI (`copilot`) and the baseline Wi-Fi/Bluetooth stack (wireless-tools, firmware, bluez) so every server starts with networking hardware ready.

## Stage 2 – Graphics preparation

- `2_pre_graph.sh`
  - Detects Intel Arc / NVIDIA / AMD GPUs and invokes `graphics_card.sh` accordingly.
  - Handles firmware, kernel modules, and driver repos.

## Stage 3 – Desktop, networking, and productivity

1. `gnome_desktop.sh`
   - Installs the minimal Ubuntu desktop stack without snaps or flatpak dependencies.
2. `3_post_graph.sh`
   - Switches to NetworkManager, installs fonts, PowerShell, the VS Code apt repo, and vendor-supplied builds of desktop apps (Postman, Draw.io, Discord, Slack, Telegram).
3. `general.sh` & `docker.sh`
   - Already covered for server usage, but rerun if you skipped them earlier and now need desktop conveniences.

## Stage 4 – Optional desktop applications

- `4_graph_optionals.sh`
  - Adds browsers, communication tools, and media utilities strictly from apt repos or upstream tarballs. Edit the script to tailor the list before executing.

## Stage 5 – Laptop extras

- `5_laptop_extras.sh`
  - Layers laptop niceties (TLP tuning, Wi-Fi power-saving, Bluetooth UI helpers, suspend tweaks, brightness rules, etc.) on top of the baseline drivers established in Stage 1.

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
command -v snap >/dev/null && echo "snap still present"
command -v flatpak >/dev/null && echo "flatpak still present"

# Stage 3
nmcli device
code --version

# Stage 5
tlp-stat -s
```

For more context on what each script installs, open it in an editor or consult the project wiki. Feel free to comment out sections you do not need before executing.
