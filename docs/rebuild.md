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
  - Verify from the laptop: a password-only attempt fails with `Permission denied (publickey)`
- [ ] Fixed address: DHCP reservation on the router (IP ↔ the Pi's MAC)
  - Verify: reboot the Pi, same address comes back
- [ ] Router config backup (System → Backup & Restore), before changing anything else on the router
- [ ] Firewall (`ufw`): default deny in, LAN-only allows, **SSH rule before `enable`**
  - Verify: a second SSH session still connects after enabling; `sudo ufw status verbose`

## 2. pihole/

Details and troubleshooting: [`pihole/README.md`](../pihole/README.md).

Prerequisite: a fixed address and the firewall (step 1).

- [ ] Firewall rules for 53 / 80 / 443 from the LAN (and 53 from the LAN's IPv6 ULA prefix)
- [ ] Download the installer, read it, run it: Quad9 (filtered, DNSSEC), default blocklist, query logging on, decline any "open firewall ports" offer
- [ ] `sudo pihole setpassword` (replace the generated password; keep it out of the repo)
  - Verify: `nslookup example.com <pi-ip>` resolves and `nslookup doubleclick.net <pi-ip>` returns `0.0.0.0`
- [ ] One client: set **both** IPv4 and IPv6 DNS by hand to the Pi (ULA address for IPv6)
  - Verify (from that client): `Resolve-DnsName <name-not-looked-up-before> -DnsOnly` returns `0.0.0.0`
- [ ] Browser "Secure DNS" off, or the browser's lookups will not show in the query log
- [ ] Network-wide coverage: **not possible with this router's DNS settings**; see "Deferred" in `pihole/README.md`

## 3. personal_website/

Not started. Prerequisite: check whether the connection is behind CGNAT, which
decides between port forwarding and a tunnel.

## 4. media_suite/

Not started. Prerequisite: USB HDD attached and mounted (`/mnt/media`).
