#!/bin/bash

# Create or resize /swapfile to match physical RAM size (one-off helper)
# Stops swap temporarily if needed, updates /etc/fstab, and re-enables swap.

if [ "$(id -u)" != "0" ]; then
  echo "EXIT[ERR]: need to run as root, exiting"
  exit 1
fi

source ./common_bash_funcs.sh || true

# Determine RAM size in KB
RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if [ -z "$RAM_KB" ]; then
  func_print_fail_message "Could not determine RAM size"
  exit 1
fi

DESIRED_KB=$RAM_KB

# Detect existing swap setup: prefer an existing swapfile; fall back to /swap.img for new creation
SWAP_FILE=""
# Look for a swapfile entry (not a /dev/ partition) in /proc/swaps
swapfile_entry=$(awk 'NR>1 && $1 !~ "^/dev/" {print $1; exit}' /proc/swaps 2>/dev/null || true)
if [ -n "$swapfile_entry" ]; then
  SWAP_FILE="$swapfile_entry"
  HAS_SWAPFILE=1
else
  # If there is a swap partition, do not manage swapfile
  if grep -q '^/dev/' /proc/swaps 2>/dev/null; then
    func_print_warn_message "Swap is provided by a partition (not a swapfile). Skipping swapfile management."
    exit 0
  fi
  # No existing swapfile or partition; use default path
  SWAP_FILE="/swap.img"
  HAS_SWAPFILE=0
fi

# Function to allocate file of size DESIRED_KB
allocate_swapfile() {
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "${DESIRED_KB}K" "$SWAP_FILE" || return 1
  elif command -v truncate >/dev/null 2>&1; then
    truncate -s "${DESIRED_KB}K" "$SWAP_FILE" || return 1
  else
    # fallback to dd
    dd if=/dev/zero of="$SWAP_FILE" bs=1K count="$DESIRED_KB" status=none || return 1
  fi
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE" >/dev/null 2>&1 || true
  return 0
}

# If swapfile exists, check size
if [ -f "$SWAP_FILE" ]; then
  EXISTING_KB=$(du -k "$SWAP_FILE" | cut -f1)
  if [ "$EXISTING_KB" -ge "$DESIRED_KB" ]; then
    func_print_info_message "Existing swapfile ($EXISTING_KB KB) >= RAM ($DESIRED_KB KB); no change needed"
    exit 0
  fi
  func_print_info_message "Resizing existing swapfile from ${EXISTING_KB}K to ${DESIRED_KB}K"
  # turn off swap
  swapoff "$SWAP_FILE" 2>/dev/null || true
  # allocate new size
  rm -f "$SWAP_FILE"
  allocate_swapfile || { func_print_fail_message "Failed to allocate swapfile"; exit 1; }
  # enable swap
  swapon "$SWAP_FILE" || { func_print_fail_message "Failed to swapon"; exit 1; }
else
  func_print_info_message "Creating new swapfile of ${DESIRED_KB}K"
  allocate_swapfile || { func_print_fail_message "Failed to allocate swapfile"; exit 1; }
  swapon "$SWAP_FILE" || { func_print_fail_message "Failed to swapon"; exit 1; }
fi

# Ensure /etc/fstab contains the swapfile entry (match by start of line)
if grep -q "^$(printf '%s' "$SWAP_FILE" | sed 's/[][^$.*/\\]/\\&/g')[[:space:]]" /etc/fstab 2>/dev/null; then
  func_print_info_message "/etc/fstab already contains an entry for $SWAP_FILE; leaving it unchanged"
else
  # Append exact tab-separated entry as requested: /swap.img	none	swap	sw	0	0 (but with current path)
  printf '%s	%s	%s	%s	%s	%s
' "$SWAP_FILE" none swap sw 0 0 >> /etc/fstab
  func_print_info_message "/etc/fstab updated with swapfile entry: $SWAP_FILE\tnone\tswap\tsw\t0\t0"
fi

func_print_info_message "Swap is configured: $(swapon --show --noheadings || true)"

exit 0
