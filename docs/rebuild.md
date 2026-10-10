# Rebuild checklist: fresh SD card to working server

The order to follow when starting from nothing. Each step links to the document
with the reasoning. Tick a box only when the "verify" line passes.

Personal values (user, hostname, IPs) are in the git-ignored `base/pi.env`;
create it from `base/pi.env.example` first.

## 0. Before touching the Pi

- [ ] Public SSH key exists on the laptop (`ls ~/.ssh/*.pub`; generate with `ssh-keygen -t ed25519`)
- [ ] `cp base/pi.env.example base/pi.env` and fill it in
- [ ] Router admin page reachable at its LAN address (credentials from its label or the password manager, never the repo)

## 1. base/: OS, SSH, fixed IP, firewall

Details and troubleshooting: [`base/README.md`](../base/README.md).

- [ ] Flash **Raspberry Pi OS Lite (64-bit)** with the **Windows/macOS/native Linux** Imager, with customisation applied (hostname, user, public-key SSH, time zone)
  - Verify: card's `bootfs` has a `user-data` modified today. If Imager had to run in WSL2, use `base/scripts/patch-cloud-init.sh` instead.
- [ ] Card in the Pi, Ethernet plugged in, power on, wait ~3 minutes
- [ ] Find the Pi's IP in the router's device list
  - Verify: `ping <pi-ip>` replies
- [ ] `ssh <pi-user>@<pi-ip>` logs in with the key, no password prompt
  - Verify: `hostnamectl` shows the right hostname
- [ ] `sudo apt update && sudo apt full-upgrade -y && sudo reboot`
  - Verify: `apt list --upgradable` is empty after reconnecting
- [ ] Confirm key-only SSH: `sudo sshd -T | grep passwordauthentication` → `no`
- [ ] Fixed IP (decision pending, see `base/README.md`)
  - Verify: reboot the Pi, same address comes back
- [ ] Firewall: allow SSH first, then enable
  - Verify: a second SSH session still connects after enabling

## 2. pihole/

Not started. Prerequisite: a fixed IP for the Pi (step 1).

## 3. personal_website/

Not started. Prerequisite: check whether the connection is behind CGNAT, which
decides between port forwarding and a tunnel.

## 4. media_suite/

Not started. Prerequisite: USB HDD attached and mounted (`/mnt/media`).
