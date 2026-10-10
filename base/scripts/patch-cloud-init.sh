#!/usr/bin/env bash
# patch-cloud-init.sh
#
# Purpose:
#   Write cloud-init config (hostname, user, SSH key, timezone) onto a freshly
#   flashed Raspberry Pi OS card by hand. Needed when Raspberry Pi Imager cannot
#   apply its own OS customisation, which happened when Imager ran inside WSL2:
#   it wrote the image and reported success, but could not mount the boot
#   partition to drop the config in. See base/README.md, "Failure modes".
#
# Inputs:
#   $1                optional card device, default /dev/sde. Must be the
#                     removable card with a partition 1 labelled "bootfs".
#   base/pi.env       PI_HOSTNAME, PI_USER, PI_TIMEZONE (see pi.env.example).
#                     Override the path with PI_ENV_FILE.
#   ~/.ssh/id_rsa.pub public key to authorise. Override with SSH_PUBKEY_FILE.
#   Prompts for the user's password (hashed locally, never written in clear).
#
# Side effects:
#   Mounts <device>1 read-write at /mnt/bootfs, replaces user-data and meta-data
#   on it, creates an empty `ssh` file, then unmounts. Originals are backed up
#   OUTSIDE the repo (~/.cache) because a second run would back up a user-data
#   containing the password hash. Uses sudo for mount/write.
#
# NOTE: if the card has already booted once, also run reset-cloud-init-state.sh,
# otherwise cloud-init treats it as the same instance and skips the users and
# SSH modules.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${PI_ENV_FILE:-${SCRIPT_DIR}/../pi.env}"
if [[ -r "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi
: "${PI_HOSTNAME:?Set PI_HOSTNAME in ${ENV_FILE} (copy base/pi.env.example)}"
: "${PI_USER:?Set PI_USER in ${ENV_FILE} (copy base/pi.env.example)}"
: "${PI_TIMEZONE:?Set PI_TIMEZONE in ${ENV_FILE} (copy base/pi.env.example)}"

DEVICE="${1:-/dev/sde}"
BOOT_PART="${DEVICE}1"
MOUNTPOINT="/mnt/bootfs"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/id_rsa.pub}"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pi-card-backup-${STAMP}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Safety checks: make sure we are about to write to the SD card and not the
# --- WSL root disk. A wrong device here would be destructive.
[[ -b "$DEVICE" ]] || { echo "ERROR: $DEVICE is not a block device" >&2; exit 1; }
[[ -b "$BOOT_PART" ]] || { echo "ERROR: $BOOT_PART not found" >&2; exit 1; }

removable="$(lsblk -dno RM "$DEVICE" | tr -d ' ')"
label="$(lsblk -no LABEL "$BOOT_PART" | head -1 | tr -d ' ')"
if [[ "$removable" != "1" || "$label" != "bootfs" ]]; then
    echo "ERROR: $DEVICE does not look like the Pi card (removable=$removable, label='$label')." >&2
    echo "       Expected removable=1 and a first partition labelled 'bootfs'." >&2
    exit 1
fi

[[ -r "$SSH_PUBKEY_FILE" ]] || { echo "ERROR: cannot read $SSH_PUBKEY_FILE" >&2; exit 1; }
PUBKEY="$(head -1 "$SSH_PUBKEY_FILE")"
case "$PUBKEY" in
    ssh-*|ecdsa-*|sk-*) ;;
    *) echo "ERROR: $SSH_PUBKEY_FILE does not look like a public key" >&2; exit 1 ;;
esac

# --- Password: prompted here so it never lands in shell history or a file.
# --- SHA-512 crypt hash is what cloud-init's `passwd:` field expects.
echo "Set a password for '${PI_USER}' on the Pi (used for sudo and the console;"
echo "SSH will be key-only):"
PASSWORD_HASH="$(openssl passwd -6)"

# --- Build the new files in a temp dir first so they can be checked before
# --- anything is written to the card.
cat > "${WORK_DIR}/user-data" <<EOF
#cloud-config
# Written by patch-cloud-init.sh on ${STAMP}.
# Equivalent to what Raspberry Pi Imager's OS customisation would have written.

hostname: ${PI_HOSTNAME}
# Keep /etc/hosts in step with the hostname so sudo does not complain.
manage_etc_hosts: true

timezone: ${PI_TIMEZONE}

users:
  - name: ${PI_USER}
    groups: users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,gpio,spi,i2c,render,sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: '${PASSWORD_HASH}'
    ssh_authorized_keys:
      - ${PUBKEY}

# Key-only SSH: password logins over the network are refused.
enable_ssh: true
ssh_pwauth: false
EOF

# NoCloud's documented key is `instance-id` (hyphen). A new value makes
# cloud-init treat the next boot as a brand-new instance and re-run the
# per-instance modules (users, SSH keys). An underscore spelling is ignored.
cat > "${WORK_DIR}/meta-data" <<EOF
dsmode: local
instance-id: manual-patch-${STAMP}
EOF

# Best-effort YAML syntax check (skipped if PyYAML is not installed).
if python3 -c 'import yaml' 2>/dev/null; then
    python3 -I -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "${WORK_DIR}/user-data"
    echo "user-data: YAML syntax OK"
else
    echo "user-data: PyYAML not installed, skipping syntax check"
fi

# --- Write to the card.
sudo mkdir -p "$MOUNTPOINT"
sudo umount "$BOOT_PART" 2>/dev/null || true
sudo mount -o rw,uid="$(id -u)",gid="$(id -g)" "$BOOT_PART" "$MOUNTPOINT"
trap 'sudo umount "$MOUNTPOINT" 2>/dev/null || true; rm -rf "$WORK_DIR"' EXIT

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cp -p "${MOUNTPOINT}/user-data" "${BACKUP_DIR}/user-data" 2>/dev/null || true
cp -p "${MOUNTPOINT}/meta-data" "${BACKUP_DIR}/meta-data" 2>/dev/null || true

cp "${WORK_DIR}/user-data" "${MOUNTPOINT}/user-data"
cp "${WORK_DIR}/meta-data" "${MOUNTPOINT}/meta-data"
# Also ask sshswitch.service to enable SSH, independent of `enable_ssh` above.
touch "${MOUNTPOINT}/ssh"

sync
echo
echo "=== meta-data now on the card ==="
cat "${MOUNTPOINT}/meta-data"
echo "=== user-data now on the card (password hash hidden) ==="
sed "s|passwd: '.*'|passwd: '<hidden>'|" "${MOUNTPOINT}/user-data"

echo
echo "Done. Originals backed up in: $BACKUP_DIR"
echo "Next: detach the reader, put the card in the Pi, power-cycle it."
