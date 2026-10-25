# media_suite: a home media server on the Pi

**Status: up and running, and working well.** The USB hard drive is mounted at
`/mnt/media` at every boot. qBittorrent (with search plugins) finds and
downloads films and shows onto it, and Jellyfin serves them to any browser or
app on the LAN. Both web UIs are reachable from the **LAN only**. Games are
the remaining piece (see [Deferred](#deferred)).

Personal details are placeholders here: `<pi-ip>`, `<pi-user>`, `<lan-cidr>`,
`<drive-uuid>`. Real values live in the git-ignored `base/pi.env`, and the web UI
passwords only in my password manager.

---

## 1. What it is

Three pieces:

1. **Storage:** the Maxone 500 GB USB HDD, attached to the Pi's folder tree at
   `/mnt/media` so programs save to it instead of the SD card.
2. **Downloads:** `qbittorrent-nox`, a BitTorrent client with no desktop window
   ("nox" = no X, Linux's graphics system). It runs in the background, is
   controlled from a browser, and searches torrent sites through plugins.
3. **Playback:** Jellyfin, a media server. It scans the folders on the drive,
   looks up posters, descriptions and episode names, and streams the files to a
   browser, phone or TV app.

| | |
|---|---|
| Drive | Maxone 500 GB 2.5″ USB 3.0 HDD, partition `sda2`, **exFAT** |
| Mount point | `/mnt/media`, from a line in `/etc/fstab` |
| **qBittorrent** | |
| Client | qBittorrent-nox 5.1.0 (Debian package), native, not Docker |
| Service | `qbittorrent-nox@<pi-user>`: runs as my user, starts at boot, waits for the drive |
| Web UI | `http://<pi-ip>:8081`, LAN only (firewall). Username `<pi-user>` |
| Torrent port | 24950, TCP + UDP (chosen at random on first start) |
| Downloads | in progress → `/mnt/media/incomplete_torrents`; finished → the category's folder (below) |
| Categories | `Movies` → `/mnt/media/torrents/movies`, `Series` → `/mnt/media/torrents/series` |
| Seeding | Ratio limit 0: a torrent stops as soon as it finishes |
| Search | Search plugins (Python scripts) in `~/.local/share/qBittorrent/nova3/engines/` |
| Config | `~/.config/qBittorrent/qBittorrent.conf`, categories in `categories.json` next to it |
| **Jellyfin** | |
| Server | Jellyfin 12.2 (official Debian repository, added by its install script) |
| Service | `jellyfin`: runs as its own `jellyfin` user, starts at boot |
| Web UI | `http://<pi-ip>:8096` on the LAN (firewall), and from anywhere for me and invited friends over [Tailscale](../README.md#remote-access-tailscale). Also UDP 7359, which lets apps find the server on the LAN |
| Libraries | **Movies** (content type Movies) → `/mnt/media/torrents/movies`; **TV Shows** (content type Shows) → `/mnt/media/torrents/series` |
| Its own data | `/var/lib/jellyfin` (database, artwork) and `/var/cache/jellyfin`, on the **SD card**, not the drive |

Why exFAT rather than ext4: the drive stays readable from Windows if I ever plug
it into a laptop. The cost is no Linux permissions and no journal (see
[2](#2-how-it-works) and [Security notes](#security-notes)). Reformatting to
ext4 erases the drive, so that is a decision for before it fills up, not after.

Why native packages, not Docker: same reasoning as Pi-hole. It keeps the layer
count down while I learn, and both packages ship ready-made systemd services.

### Day-to-day: adding something to watch

1. **Search** in qBittorrent's web UI (`http://<pi-ip>:8081`, Search tab).
2. **Download** it, choosing the category: `Movies` or `Series`. The category
   decides the folder it ends up in.
3. **Check the name** it downloaded as (`ls /mnt/media/torrents/movies` or
   `.../series`), and rename if needed, following
   [Naming](#naming-what-jellyfin-expects):
   - A film in a folder called `Movie Name (Year)`: good as is.
   - A series: needs the nested `Show Name (Year)/Season 01/` layout.
4. **Remove the torrent from qBittorrent's list** (keeping the files) before
   renaming, or it reports the files as missing (snag 14).
5. **Jellyfin picks it up** on its next scan, or straight away with real-time
   monitoring on. To force it: Dashboard → **Scan All Libraries**.

### Naming: what Jellyfin expects

Jellyfin works out what a file is from the **folder it is in** and the
**name it has**. Each library has its own folder, holding only that type.

**Movies:** one folder per film, named with the year:

```
/mnt/media/torrents/movies/
└── Movie Name (Year)/
    ├── <video file>.mp4 / .mkv
    └── <same name as the video>.srt      ← subtitles are picked up when the name matches
```

The year is what picks the right film when titles repeat. Tags such as
`[1080p]` or `[BluRay]` in the folder name are ignored, so they can stay.

**Series:** show folder, then a season folder, then episodes:

```
/mnt/media/torrents/series/
└── Show Name (Year)/
    ├── Season 01/
    │   ├── S01E01 - Episode Name.mkv
    │   └── S01E02 - Episode Name.mkv
    └── Season 02/
        └── S02E01 - Episode Name.mkv
```

- The **folders** are what matter most. A season torrent arrives as one folder
  with a long release name; it becomes `Season 0N` inside the show's folder. One
  `mv` does both (it renames when the destination does not exist yet):
  `mv "<release folder>" "Show Name (Year)/Season 02"`.
- For **episode files**, Jellyfin only strictly needs the `S01E01` part. Release
  names such as `Game.of.Thrones.S01E01.Winter.Is.Coming.1080p....mkv` work
  unchanged; `S01E01 - Episode Name` is the tidy form for anything that lacks it.
- If a film or show is matched wrongly: open it → **⋮ → Identify**.

---

## 2. How it works

```
 laptop browser ──HTTP :8081──► ufw (LAN only) ──► qbittorrent-nox (runs as <pi-user>)
                                                     │        │
       peers on the internet ◄────── :24950 ─────────┘        └── search plugins (Python)
       (outbound only: no allow rule, probably CGNAT)              ask torrent sites over HTTPS
                                                     │ writes
                                                     ▼
          /mnt/media/incomplete_torrents ──finished──► /mnt/media/torrents/{movies,series}
          └──────────────── USB HDD (exFAT), mounted at boot by /etc/fstab ─────┬───────┘
                                                                                │ reads
 laptop / phone / TV ──HTTP :8096──► ufw (LAN only) ──► jellyfin (runs as jellyfin)
                                                          └── its database and artwork on the SD card
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
- **Jellyfin can read but not change the files.** It runs as its own user,
  `jellyfin`, which is "everyone else" under `umask=022`. So it can play
  everything and cannot delete or rename anything; qBittorrent and I manage the
  files, Jellyfin only shows them.
- **Jellyfin's own data stays on the SD card, on purpose.** Its database needs
  Linux permissions and file locking, which exFAT lacks; the installer checks for
  this ("known-problematic filesystem targets"). The movies are big and read-only
  for Jellyfin, so they live on the drive; its database is small, so it lives on
  ext4.
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
- **Ports.** Each program has a port for its work and one for its control
  panel: qBittorrent talks to peers on 24950 and has its web UI on 8081 (its
  default, 8080, is Pi-hole's). Jellyfin's web UI *is* its work, on 8096, with
  UDP 7359 for apps discovering it. A headless Pi has no screen, so every
  control panel is a small web server inside the program.
- **Categories pick the folder.** A qBittorrent category is a label with its
  own save path. Choosing `Movies` or `Series` when adding a torrent sends it to
  the matching Jellyfin library's folder, so the two libraries never mix.
- **Incoming peers are blocked, on purpose for now.** The firewall has no rule
  for 24950, and the connection is probably behind CGNAT, so peers cannot start
  connections to the Pi. The Pi can still connect out to them, so downloads
  work, with fewer peers.
- **Web UI passwords are stored as hashes** (`WebUI\Password_PBKDF2` in
  qBittorrent's config). A program can check a password against it, but nobody
  can turn it back into the password, so a forgotten one can only be reset
  (snag 1).
- **Search plugins are code.** Each plugin is a short Python script that queries
  one site and returns results to qBittorrent. They run on the Pi as
  `<pi-user>`, the same user that owns the drive, so only install ones from a
  source I trust, and read them first.
- **Direct play vs. transcoding.** If the playing device understands the file's
  video format, Jellyfin sends the file as is (**direct play**), which costs the
  Pi almost nothing. If not, Jellyfin converts it on the fly (**transcoding**),
  which a Pi 4 cannot keep up with for 1080p HEVC (x265) or HDR. H.264 (x264)
  files play directly almost everywhere.

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

Then make the folders the rest of the setup uses (no `sudo`: my user owns the
drive):

```bash
mkdir -p /mnt/media/incomplete_torrents /mnt/media/torrents/movies /mnt/media/torrents/series
```

### 3.4 Firewall

```bash
sudo ufw allow from <lan-cidr> to any port 8081 proto tcp comment 'qBittorrent web UI from LAN'
sudo ufw allow from <lan-cidr> to any port 8096 proto tcp comment 'Jellyfin web UI from LAN'
sudo ufw allow from <lan-cidr> to any port 7359 proto udp comment 'Jellyfin app discovery from LAN'   # optional
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
| Downloads | Keep incomplete torrents in | `/mnt/media/incomplete_torrents` (keeps half-finished files out of Jellyfin's folders) |
| BitTorrent → Seeding Limits | When ratio reaches | `0`, then stop torrent |

Set the save paths **before the first download**: the default is `~/Downloads`
on the SD card.

### 3.9 Categories

In the left sidebar under **Categories**: right-click → **Add category**.

| Category | Save path |
|---|---|
| `Movies` | `/mnt/media/torrents/movies` |
| `Series` | `/mnt/media/torrents/series` |

Pick one in the add-torrent dialog for every download.

### 3.10 Search plugins

```bash
python3 --version       # plugins need Python 3 (3.13 on this build)
```

In the web UI: **View → Search Engine** to show the Search tab, then **Search
plugins… → Install a new one**, and paste the URL of the plugin's **raw `.py`
file**. Sources: the official repo, https://github.com/qbittorrent/search-plugins
(`nova3/engines/`), and the "Unofficial search plugins" page on its wiki
(not reviewed; read the script first).

### 3.11 Install Jellyfin

Jellyfin's install script adds Jellyfin's own package repository, then installs
from it. Download it and its checksum, check, **read it**, then run it:

```bash
curl -sO https://repo.jellyfin.org/install-debuntu.sh
curl -sO https://repo.jellyfin.org/install-debuntu.sh.sha256sum
sha256sum -c install-debuntu.sh.sha256sum      # expect: install-debuntu.sh: OK
less install-debuntu.sh
sudo bash install-debuntu.sh
```

The checksum comes from the same server as the script, so a match proves the
download is intact, not that the server is trustworthy. Reading it is the real
check before running it as root.

The installer's free-space check is about **Jellyfin's own data directory**
(`/var/lib/jellyfin`, on the SD card), not where the films go. That is
expected; see [2](#2-how-it-works).

```bash
systemctl is-enabled jellyfin    # the package enables it at boot: expect "enabled"
```

### 3.12 Jellyfin setup wizard and libraries

Open `http://<pi-ip>:8096` and follow the wizard (admin user and password: the
password manager, not the repo). Then **Dashboard → Libraries → Add Media
Library**, twice:

| Content type | Display name | Folder |
|---|---|---|
| Movies | Movies | `/mnt/media/torrents/movies` |
| Shows | TV Shows | `/mnt/media/torrents/series` |

The content type is what tells Jellyfin to look for films or for
seasons/episodes. In each library's settings, tick **Enable real-time
monitoring** so new files appear without a manual scan.

Never point a library at a folder that contains another library's folder (e.g.
Movies at `/mnt/media/torrents`): it would scan the episodes as films.

---

## 4. How to verify

| Check | Command | Expect |
|---|---|---|
| Drive mounted (Pi) | `findmnt /mnt/media` | `/dev/sda2`, `exfat`, with `uid=1000,gid=1000` |
| It is the drive, not the SD card | `df -h /mnt/media` | ~466G |
| My user can write to it | `touch /mnt/media/test && ls -l /mnt/media/test && rm /mnt/media/test` | owned by `<pi-user>`, no `Permission denied` |
| Survives a reboot | `sudo reboot`, reconnect, `findmnt /mnt/media` | same as the first row |
| qBittorrent running | `systemctl is-active qbittorrent-nox@<pi-user>` | `active` |
| qBittorrent waits for the drive | `systemctl show -p RequiresMountsFor qbittorrent-nox@<pi-user>` | includes `/mnt/media` |
| Jellyfin running | `systemctl is-active jellyfin` | `active` |
| Ports | `sudo ss -tulpn \| grep -E 'qbittorrent\|jellyfin'` | qBittorrent: TCP `*:8081`, TCP + UDP `24950`. Jellyfin: TCP `8096`, UDP `7359` |
| Firewall | `sudo ufw status` | `8081/tcp` and `8096/tcp` `ALLOW <lan-cidr>`, **no** `Anywhere` rules |
| Web UIs from the LAN | open `http://<pi-ip>:8081` and `http://<pi-ip>:8096` on the laptop | qBittorrent login; Jellyfin login |
| Jellyfin answers (laptop) | `curl -s http://<pi-ip>:8096/health` | `Healthy` |
| Downloads land in the right folder | add a torrent with a category, then `ls /mnt/media/torrents/movies` (or `series`) | it is there, and `df -h /` (SD card) has not grown |
| Jellyfin shows it | Dashboard → Scan All Libraries, then the library | poster, title and year (or episodes under the right season) |
| Direct play | play something, then Dashboard → Activity (or the playback info overlay) | **Direct playing**, not Transcoding |

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
| 9 | qBittorrent errors with `Read-only file system` | The drive was unplugged or lost power mid-write; the kernel found errors and remounted read-only (`errors=remount-ro`) | `findmnt /mnt/media` shows `ro`; `sudo dmesg \| grep -i exfat` | Stop qBittorrent and Jellyfin, `sudo umount /mnt/media`, `sudo fsck.exfat /dev/sda2`, `sudo mount -a`, start both |
| 10 | qBittorrent's web UI not reachable after install | Its default port 8080 is Pi-hole's, so the web UI could not listen | `sudo ss -tlpn \| grep 8080` shows `pihole-FTL`; nothing from qBittorrent on 8081 | Move it to 8081 (3.6) |
| 11 | A two-word search (`family guy`) finds nothing, but one word (`family`) finds it. **Hit on this build** | Most likely a plugin encoding the space twice: qBittorrent already sends `family%20guy`, and a second encoding turns it into `family%2520guy`, which the site cannot match. A single word has nothing to encode | Search with one plugin at a time (dropdown next to the search box); run one by hand: `cd ~/.local/share/qBittorrent/nova3 && python3 nova2.py <plugin> all family guy`; `grep -n "quote" engines/<plugin>.py` | Plugins window → **Check for updates**; use a plugin that handles it; or search one word and type the second into the results filter box |
| 12 | A search returns nothing from one plugin | The site is down, changed its page layout (which breaks the script), or is blocked by the carrier | Other plugins return results | **Check for updates**, or try another plugin |
| 13 | A show appears twice, or episodes show up as films | A season left in its release-named folder (each becomes its own "show"), or a library pointed at a folder containing the other library | Library → the show's folder path; Dashboard → Libraries → each library's folders | Nest seasons under one `Show Name (Year)/` ([Naming](#naming-what-jellyfin-expects)); one folder per library, never one inside the other. Then Scan All Libraries |
| 14 | qBittorrent shows "Missing files" for a torrent | The files were renamed or moved outside qBittorrent | The torrent's status; its save path no longer exists | Remove the torrent from the list with **"Also remove the content files" unticked**. To move a torrent that should stay listed, use right-click → **Set location…** |
| 15 | A film or show has the wrong poster or title | Jellyfin guessed from an unclear name (no year, extra words) | Compare with the folder name | Rename to `Name (Year)`, or **⋮ → Identify**; **⋮ → Refresh Metadata → Replace all metadata** |
| 16 | Playback buffers constantly | The device cannot play the format, so the Pi is transcoding: 1080p HEVC (x265), 10-bit, or **HDR** (e.g. the Endgame copy) | Dashboard → Activity shows **Transcoding**, with the reason | Play on a device or app that supports the format (TV apps often do; Firefox does not play HEVC), or prefer H.264 (x264) releases |
| 17 | A `System Volume Information` folder on the drive | Created by Windows when the drive was formatted at the factory | `ls /mnt/media` | Harmless; leave it |

Logs: `sudo journalctl -u qbittorrent-nox@<pi-user>` (including temporary
passwords), qBittorrent's own log in `~/.local/share/qBittorrent/logs/`,
`sudo journalctl -u jellyfin`, and Jellyfin's logs under
**Dashboard → Logs** (`/var/log/jellyfin/`).

### Security notes

- Both web UIs are reachable from the LAN only (firewall). Passwords live in the
  password manager; config files hold only hashes, and none are in this repo.
- Jellyfin runs as its own user with **read-only** access to the drive, so a
  bug in it cannot delete the library.
- **Peers see the public address.** Everyone in a torrent's swarm sees the IP
  the Pi connects from, including its public IPv6 addresses, which are unique
  to this connection. That is how BitTorrent works, and it is visible from the
  first minute of a download, not only while seeding.
- Search plugins run as `<pi-user>` with access to the drive. Install them only
  from trusted sources, and read them first.
- Before unplugging the drive: `sudo systemctl stop qbittorrent-nox@<pi-user> jellyfin`,
  then `sudo umount /mnt/media`. exFAT has no journal, so an interrupted write
  can corrupt files (snag 9).

---

## Deferred

- **Games:** browser-based emulation (the last part of the original plan).
- ~~**Watching from outside the home**~~ (done 2026-10-25): Jellyfin is still
  closed to the public internet, but I and invited friends reach it through
  Tailscale, with friends limited to port 8096. See
  [Remote access: Tailscale](../README.md#remote-access-tailscale).
- **Automating the rename step** in the day-to-day workflow.
- **A VPN for torrent traffic** (looked at 2026-10-18, put off). It would change
  routing for the whole Pi, and the Pi's public IPv6 addresses would leak around
  a tunnel that only carries IPv4.
- **Incoming peer connections:** a firewall rule for 24950 helps only if the
  router can forward it, which CGNAT probably rules out.
- **ext4 instead of exFAT,** if corruption or permissions become a problem.
- **Drive health and space:** `smartctl` (from `smartmontools`) to watch for a
  failing disk; the drive was at 102 GB of 466 GB on 2026-10-18.

---

## Status

- [x] USB HDD detected (`sda2`, exFAT, 466G)
- [x] Mounted at `/mnt/media` by `/etc/fstab` (UUID, `uid`/`gid`, `nofail`); survives a reboot
- [x] qBittorrent-nox 5.1.0 installed, running as `qbittorrent-nox@<pi-user>`, enabled at boot
- [x] qBittorrent web UI on 8081, firewall LAN-only
- [x] qBittorrent waits for the drive (`RequiresMountsFor`)
- [x] Save paths on the drive; categories `Movies` / `Series`; seeding stops at ratio 0
- [x] qBittorrent username and password changed from the defaults
- [x] Search engine on, plugins installed
- [x] Downloads confirmed landing on the drive (102 GB used, SD card unchanged)
- [x] Jellyfin 12.2 installed from its repository, running, enabled at boot
- [x] Jellyfin libraries: Movies and TV Shows, each on its own folder
- [x] Films and series organised and playing from Jellyfin on the LAN
- [ ] Confirm `sudo ufw status` shows the 8096 rule as LAN-only, not `Anywhere`
- [ ] Games / emulation
