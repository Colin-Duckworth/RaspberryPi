# base: OS install, SSH, fixed IP, updates, firewall

Shared foundation for all three sub-projects. Nothing else is built until this
works.

**Status:** OS flashed and updated, key-only SSH works, address pinned by a
router DHCP reservation, firewall active (LAN-only). Remaining items are in
[Status](#status).

Personal details (username, hostname, the Pi's IP and MAC) are not in this repo.
Below they are written as `<pi-user>`, `<pi-hostname>` and `<pi-ip>`; the real
values live in the git-ignored `base/pi.env` (template: `pi.env.example`).

---

## 1. What it is

A Raspberry Pi 4 (4 GB) running **Raspberry Pi OS Lite (64-bit)**, a Debian-based
headless Linux with no desktop, wired by Ethernet to the Brovi 5G router. It has
one admin account, key-only SSH, and (soon) a fixed address and a firewall.

Why this OS: it is headless, so RAM is not spent on a desktop; Pi-hole supports
Debian-family systems; and a CLI-only system makes me do things by hand, which is
the point of the project. 64-bit because the Pi 4 supports it and most software
targets it.

Observed on the running system: Debian GNU/Linux, kernel `6.18.50+rpt-rpi-v8`,
aarch64, cloud-init 25.2.

---

## 2. How it works

### What is on the SD card

```
microSD (64 GB)
├── bootfs   512 MB  FAT32   ← readable from Windows/macOS/Linux; mounted at /boot/firmware
│     ├── kernel8.img, config.txt, cmdline.txt, *.dtb   (the boot chain)
│     ├── user-data     ← cloud-init: hostname, user, SSH key, timezone
│     ├── meta-data     ← cloud-init: instance-id
│     └── network-config
└── rootfs   rest    ext4    ← the real OS. Starts ~2.4 GB, grows to fill the card on first boot
```

### What happens on first boot

```
power on
   │
   ▼
Pi firmware reads bootfs → loads kernel → mounts rootfs
   │
   ▼
cloud-init (NoCloud datasource) reads user-data / meta-data from /boot/firmware
   │   decides "is this a NEW instance?" by comparing instance-id with the one
   │   recorded in /var/lib/cloud
   ├─ every boot:     set hostname
   └─ once per instance:  create user, install SSH key, enable SSH, set timezone
   │
   ▼
sshd listening on :22  ──►  DHCP lease from the router  ──►  reachable on the LAN
```

The important rule is the "once per instance" part. cloud-init remembers which
instance it has already configured. If a card first boots with empty/stock
`user-data`, that instance is marked done, and fixing `user-data` afterwards does
**not** re-create the user or SSH key unless the instance changes. This is what
caused most of the pain below.

### How I talk to it

The Pi is just a computer on the router's LAN. Laptop and Pi are on the same
subnet, so traffic is switched by MAC address (ARP resolves IP → MAC); it is not
routed or NAT'd. The router is involved only for DHCP, and for traffic leaving
the LAN. Everything after the first flash is done over SSH.

---

## 3. Setup from scratch

### 3.1 Flash the card

1. **Use the Windows (or macOS/native Linux) build of Raspberry Pi Imager**, not a
   Linux build inside WSL2. See [Failure modes](#5-failure-modes-and-troubleshooting)
   for why.
2. OS: *Raspberry Pi OS (other)* → **Raspberry Pi OS Lite (64-bit)**.
3. Storage: the ~60 GB microSD. Check the size; flashing erases it.
4. OS customisation (gear icon / *Edit settings*):

   | Setting | Value | Why |
   |---|---|---|
   | Hostname | `<pi-hostname>` | Name for the Pi on the LAN |
   | Username / password | `<pi-user>` (not `pi`) | `pi` is the first name anyone tries |
   | Wi-Fi | blank | Wired on purpose: a DNS server should not depend on Wi-Fi |
   | Locale | my time zone | Correct timestamps in logs matter when diagnosing |
   | Enable SSH | yes, **public-key only**, paste `~/.ssh/id_*.pub` | Keys beat passwords; no password to brute-force |

5. Click **Write**, and answer **Yes** when asked to apply the customisation.
6. Eject, put the card in the Pi, plug in Ethernet, then power.

> If Imager cannot apply customisation (or you must flash from WSL2), write the
> same settings by hand with `scripts/patch-cloud-init.sh`. See below.

### 3.2 Find the Pi and log in

1. Wait ~3 minutes: the first boot resizes the filesystem and may reboot once.
2. Find the IP in the router's admin page (device list), or scan for port 22.
3. `ssh <pi-user>@<pi-ip>`. The first connection asks you to trust the host key
   fingerprint; type `yes`.

`<pi-hostname>.local` works from machines where mDNS works, but usually **not**
from WSL2 (multicast does not cross its virtual NAT). Use the IP there.

### 3.3 Patching the card by hand (fallback)

Only needed when Imager failed to write the customisation. From a Linux shell
that can see the card (in WSL2 via `usbipd`; see below):

```bash
cp base/pi.env.example base/pi.env      # then edit: hostname, user, timezone
bash base/scripts/patch-cloud-init.sh /dev/sdX          # writes user-data + meta-data
# Only if this card has ALREADY booted once:
bash base/scripts/reset-cloud-init-state.sh /dev/sdX    # makes next boot a first boot
```

Check `lsblk` first: the device must be the removable ~60 GB card. Both scripts
refuse to run unless the device is removable and its partitions are labelled
`bootfs`/`rootfs`, but read the device name yourself too.

### 3.4 Seeing the card from WSL2 (workaround, not recommended)

WSL2 is a VM and does not see Windows USB devices. `usbipd-win` forwards one in:

```powershell
winget install --interactive --exact dorssel.usbipd-win     # once
usbipd list                                                 # find the card reader's BUSID
usbipd bind --busid <BUSID>                                 # once per device, admin shell
usbipd attach --wsl --busid <BUSID>                         # every time it is re-plugged
```

Then in WSL, the device node is `root:disk 660`, so a tool running as your user
cannot open it:

```bash
sudo chmod 666 /dev/sdX /dev/sdX1 /dev/sdX2   # resets on every re-attach
```

The BUSID can change when the reader moves to another USB port.

### 3.5 First things to do once logged in

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

### 3.6 Fixed address: router DHCP reservation

Chosen over a static address on the Pi because the router stays the single
source of truth for who has which address, and the Pi's network config stays
"just DHCP". In the router's DHCP page, add a row to the *IP and MAC Address
Binding List*: the Pi's current IP and its MAC (`ip link show eth0` on the Pi).
Reboot the Pi and confirm the same address comes back.

Limit: this only works while the router's DHCP server is the one answering. If
Pi-hole ever takes over DHCP (see `pihole/README.md`, "Deferred"), the Pi needs a
real static address on itself first.

### 3.7 Firewall (`ufw`)

`ufw` is a thin, readable front end over nftables. It is not installed by
default on Pi OS Lite. Default stance: nothing in unless allowed, everything
out. Every allow rule is restricted to the home LAN, so none of these services is
reachable from outside it.

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Rules go in BEFORE enabling, so SSH is never cut off.
sudo ufw allow from <lan-cidr> to any port 22 proto tcp comment 'SSH from LAN'
# (Pi-hole rules, see pihole/README.md)
sudo ufw allow from <lan-cidr> to any port 53  comment 'DNS (tcp+udp) from LAN'
sudo ufw allow from <lan-cidr> to any port 80  proto tcp comment 'Pi-hole admin UI'
sudo ufw allow from <lan-cidr> to any port 443 proto tcp comment 'Pi-hole admin UI (TLS)'
sudo ufw allow from <lan-ula-cidr> to any port 53 comment 'DNS (v6 ULA) from LAN'

sudo ufw show added        # review BEFORE enabling
sudo ufw enable            # answer y; the open session survives
sudo ufw status verbose
```

Then, **from a second terminal**, prove SSH still works before closing the first.
`sudo ufw disable` is the instant undo.

Things worth knowing:

- **Blocked means dropped, not refused.** A closed port simply times out instead
  of answering "connection refused". That is `deny`'s behaviour, and it tells a
  scanner nothing.
- **A rule with an IPv4 source does not cover IPv6.** `from 192.168.x.0/24`
  matches only IPv4, so IPv6 traffic needs its own rule (the `<lan-ula-cidr>` line).
- **A DHCP request has source `0.0.0.0`**, so a LAN-sourced rule will not match
  it. This matters only if the Pi ever serves DHCP.

---

## 4. How to verify

| Check | Command (on the Pi unless noted) | Expected |
|---|---|---|
| Reachable | `ping -c 2 <pi-ip>` (laptop) | replies, 0% loss |
| Key login works | `ssh <pi-user>@<pi-ip>` (laptop) | no password prompt |
| Identity | `hostnamectl` | correct hostname, Debian, aarch64 |
| Time zone | `timedatectl` | correct zone, "System clock synchronized: yes" |
| Disk grew | `df -h /` | root fs ≈ card size, not ≈ 2.4 GB |
| SSH key-only | `sudo sshd -T \| grep -E 'passwordauthentication\|pubkeyauthentication'` | `passwordauthentication no`, `pubkeyauthentication yes` |
| SSH key-only, from outside | `ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no <pi-user>@<pi-ip>` (laptop) | `Permission denied (publickey)`: the server does not even offer passwords |
| Firewall active | `sudo ufw status verbose` | `active`, `deny (incoming)`, only LAN-sourced allows |
| Firewall drops the rest | `timeout 3 bash -c 'echo > /dev/tcp/<pi-ip>/8080'` (laptop) | hangs until the timeout (dropped), not an instant refusal |
| Address is pinned | reboot the Pi, then `ip -br a` | same address as before |
| Network view | `ip -br a`, `ip route`, `ip neigh` | eth0 has the LAN IP; default route via the router |
| cloud-init ran | `cloud-init status --long` | `status: done` |
| Updates applied | `apt list --upgradable` | empty |

---

## 5. Failure modes and troubleshooting

These all happened during the first build. In order, because each fix revealed
the next problem. **Root cause for most: Imager running inside WSL2.**

| # | Symptom | Cause | How to confirm | Fix |
|---|---|---|---|---|
| 1 | Card shows in Windows Explorer but not in Imager's *Choose Storage* | WSL2 is a VM with its own virtual disks; it cannot see Windows USB devices | `lsblk` in WSL shows no 60 GB disk | Flash from the Windows Imager, **or** forward the reader with `usbipd` (3.4) |
| 2 | `Cannot open storage device '/dev/sde'` | Device node is `root:disk 660`; my user is not in `disk`; no polkit agent in WSL to ask for permission | `ls -l /dev/sde` | `sudo chmod 666 /dev/sde*` (resets on re-attach) |
| 3 | `ssh <pi-hostname>.local` → *Could not resolve hostname* | `.local` is mDNS multicast, which does not cross WSL2's virtual NAT | `ping.exe <name>` from Windows also fails, and the router list shows the Pi at some IP | Use the IP from the router's device list |
| 4 | Pi is up and pings, but SSH → *Connection refused*; router names it `raspberrypi` | Imager reported "Write Successful" but never wrote the customisation (likely could not mount the boot partition under WSL; not proven) | Mount the card read-only: `user-data` still has the image-build timestamp, no `<pi-user>` in `etc/passwd`, `sshswitch.service` only | Write the config by hand: `patch-cloud-init.sh` |
| 5 | After patching, hostname is right but there is still no user and no SSH | The card had already booted once with stock config, so cloud-init considered it the same instance and skipped the once-per-instance modules. My patch also wrote `instance_id` (underscore); the documented key is `instance-id` (hyphen), so it was ignored | `/var/log/cloud-init.log` says `config-ssh already ran (freq=once-per-instance)`; `0 failures`, no tracebacks | `reset-cloud-init-state.sh`, then power-cycle |

### Reading a card that will not boot properly

Put the card back in a reader, mount read-only (nothing on it changes), and
look:

```bash
sudo mkdir -p /mnt/bootfs /mnt/rootfs
sudo mount -o ro /dev/sdX1 /mnt/bootfs
sudo mount -o ro /dev/sdX2 /mnt/rootfs
cat /mnt/rootfs/etc/hostname
grep <pi-user> /mnt/rootfs/etc/passwd
ls -la /mnt/bootfs/user-data                     # image-build date = never customised
grep -iE 'warn|error|fail|traceback' /mnt/rootfs/var/log/cloud-init.log | tail -40
tail -30 /mnt/rootfs/var/log/cloud-init-output.log
sudo umount /mnt/bootfs /mnt/rootfs
```

### Other things that look alarming and are not

- **"Wi-Fi is currently blocked by rfkill"** at login: Pi OS blocks the radio until
  a regulatory country is set. The Pi is wired on purpose, so leave it blocked.
- **"The authenticity of host ... can't be established"** on the first SSH: new
  host keys were generated on first boot. Expected once; after a reflash you will
  get *REMOTE HOST IDENTIFICATION HAS CHANGED* and need `ssh-keygen -R <pi-ip>`.
- **The Pi's IP changes between boots:** it comes from DHCP. Fixed by the router
  reservation (3.6); Pi-hole needs a stable address.
- **The Pi's public IPv6 address changes:** the carrier rotates the IPv6 prefix
  (seen within hours of the first boot: the old `2001:…` address became
  *deprecated* and a new one appeared). Never use a public IPv6 address as a DNS
  server or in a firewall rule. The router's private ULA prefix (`fd..::/64`) has
  been stable so far and is what the LAN-only IPv6 rules use.
- **Tests run from WSL appear to come from the laptop's address:** WSL2 is NAT'd
  by Windows, so the Pi (and Pi-hole's log) cannot tell WSL from Windows.

### Lock-out precautions (before touching the firewall or sshd)

SSH is the only door. A bad firewall rule, wrong static IP, or broken
`sshd_config` means the fix is pulling the SD card and editing it from a laptop.
Allow port 22 *before* enabling any firewall, and keep one SSH session open while
testing changes from a second.

---

## Status

- [x] OS chosen and flashed (Raspberry Pi OS Lite 64-bit)
- [x] First-boot config applied: hostname, admin user, SSH key, time zone
- [x] Key-only SSH login from the laptop works
- [x] Card-patching scripts in `scripts/`, with git-ignored `pi.env`
- [x] `apt full-upgrade` and reboot (0 upgradable afterwards)
- [x] `sshd` is key-only (password attempt refused with `Permission denied (publickey)`)
- [x] Fixed address: router DHCP reservation (decided, see 3.6)
- [x] Firewall: `ufw` active, default deny in, LAN-only allows for 22/53/80/443
- [ ] Router config backup (System → Backup & Restore). Not confirmed done.
- [ ] Check CGNAT (compare router WAN IP with `curl -4 ifconfig.me`) for sub-project 2
- [ ] `sudo sshd -T` confirmation on the Pi itself (the outside-in test passed, but
      the effective config has not been printed)

**Decision made:** fixed IP via router reservation. Revisit only if Pi-hole takes
over DHCP, which would need a static address on the Pi itself first.
