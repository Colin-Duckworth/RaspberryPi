#!/usr/bin/env bash
# reset-cloud-init-state.sh
#
# Purpose:
#   Make the Pi's NEXT boot a true first boot as far as cloud-init is concerned,
#   so it re-applies the user-data written by patch-cloud-init.sh (create the
#   user, authorise the SSH key, enable SSH).
#
# Why this is needed:
#   cloud-init records which "instance" it has configured in /var/lib/cloud.
#   Most modules (users, ssh keys, ...) run once per instance. If the card has
#   already booted with stock, empty user-data, that instance is marked done and
#   later boots with real user-data skip those modules (only the hostname, which
#   runs every boot, changes). This is the offline equivalent of running
#   `cloud-init clean` on the Pi.
#
# Inputs:
#   $1             optional card device, default /dev/sde. Must be removable,
#                  with partition 1 labelled "bootfs" and 2 labelled "rootfs".
#   base/pi.env    PI_USER, used to check that our user-data is in place.
#
# Side effects:
#   - Mounts both partitions read-write (/mnt/bootfs, /mnt/rootfs), then
#     unmounts them.
#   - Moves everything in /var/lib/cloud except "seed" to a timestamped backup
#     directory on the same filesystem. Nothing is deleted.
#   - Rewrites /boot/firmware/meta-data with a fresh `instance-id`.
#   - Creates an empty /boot/firmware/ssh file (consumed by sshswitch.service).
#   Uses sudo for mounting and writing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${PI_ENV_FILE:-${SCRIPT_DIR}/../pi.env}"
if [[ -r "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi
: "${PI_USER:?Set PI_USER in ${ENV_FILE} (copy base/pi.env.example)}"

DEVICE="${1:-/dev/sde}"
BOOT_PART="${DEVICE}1"
ROOT_PART="${DEVICE}2"
BOOT_MNT="/mnt/bootfs"
ROOT_MNT="/mnt/rootfs"
STAMP="$(date +%Y%m%d-%H%M%S)"

# --- Safety checks: refuse anything that is not the removable card with the
# --- expected partition labels. WSL's own root disk must never be touched.
[[ -b "$DEVICE" && -b "$BOOT_PART" && -b "$ROOT_PART" ]] \
    || { echo "ERROR: $DEVICE, $BOOT_PART or $ROOT_PART missing" >&2; exit 1; }

removable="$(lsblk -dno RM "$DEVICE" | tr -d ' ')"
boot_label="$(lsblk -no LABEL "$BOOT_PART" | head -1 | tr -d ' ')"
root_label="$(lsblk -no LABEL "$ROOT_PART" | head -1 | tr -d ' ')"
if [[ "$removable" != "1" || "$boot_label" != "bootfs" || "$root_label" != "rootfs" ]]; then
    echo "ERROR: $DEVICE does not look like the Pi card" >&2
    echo "       removable=$removable bootfs-label='$boot_label' rootfs-label='$root_label'" >&2
    exit 1
fi

sudo mkdir -p "$BOOT_MNT" "$ROOT_MNT"
sudo umount "$BOOT_PART" 2>/dev/null || true
sudo umount "$ROOT_PART" 2>/dev/null || true
sudo mount -o rw "$BOOT_PART" "$BOOT_MNT"
sudo mount -o rw "$ROOT_PART" "$ROOT_MNT"
# Always unmount, even if a later step fails, so the card is left clean.
trap 'sudo umount "$BOOT_MNT" "$ROOT_MNT" 2>/dev/null || true' EXIT

# --- Sanity check: the user-data we want applied must actually be there.
if ! sudo grep -q "name: ${PI_USER}" "${BOOT_MNT}/user-data"; then
    echo "ERROR: ${BOOT_MNT}/user-data does not contain our config." >&2
    echo "       Run patch-cloud-init.sh first." >&2
    exit 1
fi

# --- Move aside cloud-init's recorded state (everything except the seed dir).
CLOUD_DIR="${ROOT_MNT}/var/lib/cloud"
BACKUP_DIR="${ROOT_MNT}/var/lib/cloud-state-backup-${STAMP}"
sudo mkdir -p "$BACKUP_DIR"
for entry in "$CLOUD_DIR"/*; do
    [[ -e "$entry" ]] || continue
    [[ "$(basename "$entry")" == "seed" ]] && continue
    sudo mv "$entry" "$BACKUP_DIR/"
done
echo "cloud-init state moved to: /var/lib/cloud-state-backup-${STAMP} (on the card)"

# --- meta-data: NoCloud's documented key is `instance-id` (hyphen). A fresh
# --- value is belt and braces on top of the state reset above.
printf 'dsmode: local\ninstance-id: manual-patch-%s\n' "$STAMP" \
    | sudo tee "${BOOT_MNT}/meta-data" >/dev/null

# --- Ask sshswitch.service to enable SSH on this boot.
sudo touch "${BOOT_MNT}/ssh"

sync
echo
echo "=== bootfs: files that matter ==="
ls -la "${BOOT_MNT}/ssh" "${BOOT_MNT}/user-data" "${BOOT_MNT}/meta-data"
echo "=== meta-data ==="
sudo cat "${BOOT_MNT}/meta-data"
echo "=== /var/lib/cloud now (should be just 'seed' or empty) ==="
ls -la "$CLOUD_DIR"
echo
echo "Done. Detach the reader, put the card in the Pi, power-cycle it."
