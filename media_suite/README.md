# media_suite: storage, downloads, and (later) playback

**Status:** the USB hard drive is mounted at `/mnt/media` at every boot, and
qBittorrent runs on the Pi as a service, downloading onto that drive. Its web UI
is reachable from the **LAN only**. The playback side (a web UI to browse and
play the files) is **not started** yet (see [Deferred](#deferred)).

Personal details are placeholders here: `<pi-ip>`, `<pi-user>`, `<lan-cidr>`,
`<drive-uuid>`. Real values live in the git-ignored `base/pi.env`, and the web UI
password only in my password manager.

---

## 1. What it is

Two pieces so far:

1. **Storage:** the Maxone 500 GB USB HDD, attached to the Pi's folder tree at
   `/mnt/media` so programs can save to it instead of the SD card.
2. **Downloads:** `qbittorrent-nox`, a BitTorrent client with no desktop window
   ("nox" = no X, Linux's graphics system). It runs in the background and is
   controlled from a browser.

| | |
|---|---|
| Drive | Maxone 500 GB 2.5″ USB 3.0 HDD, partition `sda2`, **exFAT** |
| Mount point | `/mnt/media`, from a line in `/etc/fstab` |
| Client | qBittorrent-nox 5.1.0 (Debian package), native, not Docker |
| Service | `qbittorrent-nox@<pi-user>`: runs as my user, starts at boot, waits for the drive |
| Web UI | `http://<pi-ip>:8081`, LAN only (firewall). Username `<pi-user>` |
| Torrent port | 24950, TCP + UDP (chosen at random on first start) |
| Downloads | in progress → `/mnt/media/incomplete_torrents`, finished → `/mnt/media/torrents` |
| Seeding | Ratio limit 0: a torrent stops as soon as it finishes |
| Search | Search plugins (Python scripts) in `~/.local/share/qBittorrent/nova3/engines/` |
| Config file | `~/.config/qBittorrent/qBittorrent.conf` |

Why exFAT rather than ext4: the drive stays readable from Windows if I ever plug
it into a laptop. The cost is no Linux permissions and no journal (see
[2](#2-how-it-works) and [Security notes](#security-notes)). Reformatting to
ext4 erases the drive, so that is a decision for before it fills up, not after.

Why the Debian package, not Docker: same reasoning as Pi-hole. It keeps the
layer count down while I learn, and the package ships a ready-made systemd
service.

---

## 2. How it works

```
 laptop browser ──HTTP :8081──► ufw (LAN only) ──► qbittorrent-nox ◄── runs as <pi-user>
                                                     │      │
         peers on the internet ◄──── :24950 ─────────┘      └── search plugins (Python)
         (outbound only: no allow rule,                          ask torrent sites over HTTPS
          and probably behind CGNAT)
                                                     │ writes
                                                     ▼
                     /mnt/media/incomplete_torrents ──finished──► /mnt/media/torrents
                     └──────────── USB HDD (exFAT), mounted at boot by /etc/fstab ─────────┘
```

How each piece is decided:

- **Detected is not mounted.** Plugging the drive in makes the kernel create
  `/dev/sda` (the drive) and `/dev/sda2` (its data partition), and `lsblk` lists
  them, but no folder leads to them. Linux has one folder tree starting at `/`,
  not drive letters. A drive is used by **mounting** it onto an empty folder;
  after that, anything saved in the folder is written to the drive. Raspberry Pi
  OS Lite has no desktop helper to do this automatically.
- **`mount` vs. `/etc/fstab`.** `mount` attaches the drive until the next
  reboot. A line in `/etc/fstab` makes systemd mount it at every boot.
- **UUID, not `/dev/sda2`.** `sda` names are handed out in detection order, so a
  second USB drive could turn the Maxone into `sdb`. The UUID is stored on the
  drive itself and never changes.
- **Who owns the files.** exFAT has no Linux owners or permissions, so the
  kernel gives every file on it one owner at mount time: root, unless told
  otherwise. qBittorrent runs as `<pi-user>`, so the mount options
  `uid=1000,gid=1000` make my user the owner, and `umask=022` gives the owner
  read/write and everyone else read-only. `chmod` and `chown` do not work on this
  drive; the mount options are the only control.
- **`nofail`.** Without it, a missing drive stops the boot in emergency mode,
  which on a headless Pi means no SSH. With it, the Pi boots without the drive.
- **qBittorrent waits for the drive.** `nofail` creates a new trap: if the drive
  fails to mount, `/mnt/media` is just an empty folder on the SD card, and
  qBittorrent would quietly fill the SD card. A systemd drop-in with
  `RequiresMountsFor=/mnt/media` means the service does not start at all unless
  the drive is mounted.
- **The `@` in the service name.** The package ships a *template* unit,
  `qbittorrent-nox@.service`, containing `User=%i`. Whatever follows the `@`
  becomes the user it runs as, so `qbittorrent-nox@<pi-user>` runs as me and
  keeps its settings in my home folder.
- **Two ports, two jobs.** 24950 is the work (talking to peers). 8081 is the
  control panel: a small web server inside qBittorrent, because a headless Pi
  has no screen for an app window. qBittorrent's default web port is 8080, but
  Pi-hole's admin UI already holds it, and only one program can listen on a port.
- **Incoming peers are blocked, on purpose for now.** The firewall has no rule
  for 24950, and the connection is probably behind CGNAT, so peers cannot start
  connections to the Pi. The Pi can still connect out to them, so downloads
  work, with fewer peers.
- **The web UI password is stored as a hash** (`WebUI\Password_PBKDF2` in the
  config file). qBittorrent can check a password against it, but nobody can
  turn it back into the password, so a forgotten one can only be reset (snag 1).
- **Search plugins are code.** Each plugin is a short Python script that queries
  one site and returns results to qBittorrent. They run on the Pi as
  `<pi-user>`, the same user that owns the drive, so only install ones from a
  source I trust, and read them first.

---

## 3. Setup from scratch

Prerequisites: [`base/`](../base/README.md) (SSH, firewall), and
[`pihole/`](../pihole/README.md) with its admin UI on 8080 if Pi-hole is on the
same Pi (that is why qBittorrent's web UI goes on 8081).

### 3.1 Identify the drive (on the Pi)

```bash
lsblk -f        # the drive's partition (sda2 here), its format, and its UUID
id              # my user's uid and gid (1000 on this build)
```

If the drive is new or needs wiping: `sudo mkfs.exfat -L Maxone /dev/sda2`
(from `exfatprogs`). **This erases the partition**; check the device name twice.

### 3.2 Mount it once by hand

```bash
sudo mkdir -p /mnt/media
sudo mount -t exfat -o uid=1000,gid=1000 /dev/sda2 /mnt/media
df -h /mnt/media        # ~466G means the drive; ~58G would mean the SD card
sudo umount /mnt/media
```

Not required, but it shows what mounting is before making it permanent.

### 3.3 Mount it at every boot

```bash
sudo cp /etc/fstab /etc/fstab.bak       # a broken fstab can stop the Pi booting
sudo nano /etc/fstab
```

Add one line:

```
UUID=<drive-uuid>  /mnt/media  exfat  defaults,uid=1000,gid=1000,umask=022,nofail,x-systemd.device-timeout=10s  0  0
```

| Field | Value | Meaning |
|---|---|---|
| What | `UUID=<drive-uuid>` | Which drive |
| Where | `/mnt/media` | Mount point |
| Type | `exfat` | File system format |
| Options | see [2](#2-how-it-works) | Owner, permissions, `nofail`, wait at most 10 s at boot |
| Dump | `0` | Old backup tool setting; always 0 |
| Check order | `0` | No disk check at boot (the SD card's root uses `1`) |

Test **before** rebooting, while SSH still works:

```bash
sudo systemctl daemon-reload    # systemd re-reads fstab
findmnt --verify                # syntax check: no errors
sudo mount -a                   # mount everything in fstab; errors mean fix the line now
```

### 3.4 Firewall

```bash
sudo ufw allow from <lan-cidr> to any port 8081 proto tcp comment 'qBittorrent web UI from LAN'
```

No rule for the torrent port (see [2](#2-how-it-works)).

### 3.5 Install qBittorrent and start the service

```bash
sudo apt install -y qbittorrent-nox
sudo systemctl enable --now qbittorrent-nox@<pi-user>
```

`enable` starts it at every boot; `--now` also starts it immediately.

### 3.6 Move the web UI to 8081

The first start writes the config file with the web UI on 8080, which Pi-hole
holds. qBittorrent rewrites its config file when it exits, so **stop it before
editing**, or the change is overwritten:

```bash
sudo systemctl stop qbittorrent-nox@<pi-user>
nano ~/.config/qBittorrent/qBittorrent.conf     # under [Preferences]: WebUI\Port=8081
sudo systemctl start qbittorrent-nox@<pi-user>
```

### 3.7 Make qBittorrent wait for the drive

```bash
sudo systemctl edit qbittorrent-nox@<pi-user>
```

In the space the editor marks for changes:

```
[Unit]
RequiresMountsFor=/mnt/media
```

This saves `/etc/systemd/system/qbittorrent-nox@<pi-user>.service.d/override.conf`,
a drop-in that adds to the package's unit without editing it (package updates
would overwrite a direct edit). Then:

```bash
sudo systemctl restart qbittorrent-nox@<pi-user>
```

### 3.8 First login and settings

qBittorrent 5 has no default password. When none is set, it makes a temporary
one at every start and writes it to its log:

```bash
sudo journalctl -u qbittorrent-nox@<pi-user> --since "5 min ago" --no-pager | grep -i password
```

Log in at `http://<pi-ip>:8081` as `admin` with that password (copy and paste
it: five wrong attempts ban the IP, snag 2), then in **Tools → Options**:

| Where | Setting | Value |
|---|---|---|
| WebUI → Authentication | Username, password | `<pi-user>`, a real password, saved in the password manager |
| Downloads | Default Save Path | `/mnt/media/torrents` |
| Downloads | Keep incomplete torrents in | `/mnt/media/incomplete_torrents` (keeps half-finished files out of the folder a media player will scan later) |
| BitTorrent → Seeding Limits | When ratio reaches | `0`, then stop torrent |

Set the save paths **before the first download**: the default is `~/Downloads`
on the SD card.

### 3.9 Search plugins

```bash
python3 --version       # plugins need Python 3 (3.13 on this build)
```

In the web UI: **View → Search Engine** to show the Search tab, then **Search
plugins… → Install a new one**, and paste the URL of the plugin's **raw `.py`
file**. Sources: the official repo, https://github.com/qbittorrent/search-plugins
(`nova3/engines/`), and the "Unofficial search plugins" page on its wiki
(not reviewed; read the script first).

---

## 4. How to verify

| Check | Command | Expect |
|---|---|---|
| Drive mounted (Pi) | `findmnt /mnt/media` | `/dev/sda2`, `exfat`, with `uid=1000,gid=1000` |
| It is the drive, not the SD card | `df -h /mnt/media` | ~466G |
| My user can write to it | `touch /mnt/media/test && ls -l /mnt/media/test && rm /mnt/media/test` | owned by `<pi-user>`, no `Permission denied` |
| Survives a reboot | `sudo reboot`, reconnect, `findmnt /mnt/media` | same as the first row |
| Service running | `systemctl is-active qbittorrent-nox@<pi-user>` | `active` |
| Service waits for the drive | `systemctl show -p RequiresMountsFor qbittorrent-nox@<pi-user>` | includes `/mnt/media` |
| Ports | `sudo ss -tulpn \| grep qbittorrent` | TCP `*:8081`; TCP and UDP `24950` |
| Firewall | `sudo ufw status` | `8081/tcp ALLOW <lan-cidr>`, **no** `Anywhere` rule for 8081 |
| Web UI from the LAN | open `http://<pi-ip>:8081` on the laptop | login page |
| Downloads land on the drive | add a small torrent you may share (e.g. a Debian netinst image), then `ls /mnt/media/torrents` | the file is there, and `df -h /` (SD card) has not grown |

---

## 5. Failure modes and troubleshooting

| # | Symptom | Cause | How to confirm | Fix |
|---|---|---|---|---|
| 1 | Web UI password forgotten. **Hit on this build** | Only a hash is stored; it cannot be read back | `grep Password_PBKDF2 ~/.config/qBittorrent/qBittorrent.conf` shows a line (do not paste its value anywhere) | Stop the service, delete that line (`sed -i '/^WebUI\\Password_PBKDF2/d' ~/.config/qBittorrent/qBittorrent.conf`), start it, read the new temporary password from `journalctl` (3.8), set a real one |
| 2 | Login page: "Your IP address has been banned after too many failed authentication attempts". **Hit on this build** | 5 failed logins ban the IP for 1 hour (defaults) | The message itself | The ban list is in memory: `sudo systemctl restart qbittorrent-nox@<pi-user>` clears it. After a reset, use only the **newest** temporary password: every restart makes a new one |
| 3 | 8081 allowed from `Anywhere` (IPv4 and IPv6) instead of the LAN. **Caught on review** | A setup guide's `sudo ufw allow 8081/tcp`. With the Pi's public IPv6 addresses, only the router stood between the internet and the login page | `sudo ufw status` shows `8081/tcp ALLOW Anywhere` | Add the LAN rule (3.4) first, then `sudo ufw delete allow 8081/tcp` (removes both v4 and v6) |
| 4 | Downloads would have gone to the SD card. **Avoided on this build** | Default save path `~/Downloads`, and the drive was detected but not mounted | `lsblk` shows `sda2` with no mount point; `df -h ~/Downloads` shows the SD card | Mount the drive (3.3) and set the save paths (3.8) before the first download |
| 5 | qBittorrent not running after boot; web UI does not load | The drive did not mount, so `RequiresMountsFor` held the service back (by design) | `findmnt /mnt/media` prints nothing; `systemctl status qbittorrent-nox@<pi-user>` mentions the mount | Check the cable and `lsblk`; `sudo mount -a`; `sudo systemctl start qbittorrent-nox@<pi-user>` |
| 6 | Pi does not come back after a reboot (no ping, no SSH) | A bad `/etc/fstab` line without `nofail`, or a typo that stops boot | Needs a screen and keyboard, or the SD card in another Linux machine | Restore `/etc/fstab.bak`. Prevention: `findmnt --verify` and `sudo mount -a` before every reboot (3.3) |
| 7 | `Permission denied` writing to `/mnt/media` as my user | Mounted without `uid=`/`gid=`, so root owns everything | `ls -ld /mnt/media` shows `root root`; `findmnt /mnt/media` has no `uid=1000` | Fix the fstab options, `sudo umount /mnt/media`, `sudo mount -a` |
| 8 | `chmod: Operation not permitted` on the drive | exFAT stores no Linux permissions | Any `chmod` on `/mnt/media` | Expected. Change `uid`/`gid`/`umask` in fstab instead |
| 9 | qBittorrent errors with `Read-only file system` | The drive was unplugged or lost power mid-write; the kernel found errors and remounted read-only (`errors=remount-ro`) | `findmnt /mnt/media` shows `ro`; `sudo dmesg \| grep -i exfat` | `sudo systemctl stop qbittorrent-nox@<pi-user>`, `sudo umount /mnt/media`, `sudo fsck.exfat /dev/sda2`, `sudo mount -a`, start the service |
| 10 | Web UI not reachable after install | Its default port 8080 is Pi-hole's, so the web UI could not listen | `sudo ss -tlpn \| grep 8080` shows `pihole-FTL`; nothing from qBittorrent on 8081 | Move it to 8081 (3.6) |
| 11 | A search returns nothing from one plugin | The site is down, changed its page layout (which breaks the script), or is blocked by the carrier | Other plugins return results | Plugins window → **Check for updates**, or try another plugin |
| 12 | A `System Volume Information` folder on the drive | Created by Windows when the drive was formatted at the factory | `ls /mnt/media` | Harmless; leave it |

Logs: `sudo journalctl -u qbittorrent-nox@<pi-user>` (the service, including
temporary passwords) and qBittorrent's own log in
`~/.local/share/qBittorrent/logs/`.

### Security notes

- The web UI is reachable from the LAN only (firewall). Its password lives in
  the password manager; the config file holds only a hash, and the config file
  is not in this repo.
- **Peers see the public address.** Everyone in a torrent's swarm sees the IP
  the Pi connects from, including its public IPv6 addresses, which are unique
  to this connection. That is how BitTorrent works, and it is visible from the
  first minute of a download, not only while seeding. Only download what you
  are allowed to share.
- Search plugins run as `<pi-user>` with access to the drive. Install them only
  from trusted sources, and read them first.
- Before unplugging the drive: `sudo systemctl stop qbittorrent-nox@<pi-user>`,
  then `sudo umount /mnt/media`. exFAT has no journal, so an interrupted write
  can corrupt files (snag 9).

---

## Deferred

- **Playback:** a web UI to browse and play what is on the drive (the original
  goal of this sub-project). Candidates and the Pi 4's limits (it can play most
  files directly, but struggles to convert video on the fly) still to be
  looked at. nginx could later sit in front of it as a reverse proxy.
- **Games:** browser-based emulation, after playback.
- **A VPN for torrent traffic** (looked at 2026-10-18, put off). It would change
  routing for the whole Pi, and the Pi's public IPv6 addresses would leak around
  a tunnel that only carries IPv4.
- **Incoming peer connections:** a firewall rule for 24950 helps only if the
  router can forward it, which CGNAT probably rules out (CGNAT check is pending in
  [`personal_website/`](../personal_website/README.md#deferred)).
- **ext4 instead of exFAT,** if corruption or permissions become a problem.
- **Drive health:** `smartctl` (from `smartmontools`) to watch for a failing disk.

---

## Status

- [x] USB HDD detected (`sda2`, exFAT, 466G)
- [x] Mounted at `/mnt/media` by `/etc/fstab` (UUID, `uid`/`gid`, `nofail`); survives a reboot
- [x] qBittorrent-nox 5.1.0 installed, running as `qbittorrent-nox@<pi-user>`, enabled at boot
- [x] Web UI on 8081, firewall LAN-only
- [x] Service waits for the drive (`RequiresMountsFor`)
- [x] Save paths on the drive; seeding stops at ratio 0
- [x] Web UI username and password changed from the defaults
- [x] Search engine on, plugins installed
- [ ] A test download confirmed on the drive, not the SD card
- [ ] Playback web UI
- [ ] Games / emulation
