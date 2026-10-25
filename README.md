# Raspberry Pi Home Server

A Raspberry Pi 4 running three self-hosted services, built as a way to learn
networking (IP, DNS, HTTP/TLS), how the internet works end to end, and Linux
system administration.

> **The goal is understanding, not uptime.** A working setup I don't understand
> is a failure. A broken setup I can diagnose is a success.

This repo is meant to be a **reproducible record**: starting from a fresh OS
install, the docs and configs here should be enough to rebuild the whole server.

---

## The three sub-projects

| # | Sub-project | What it does | What I'm learning | Status |
|---|---|---|---|---|
| 1 | [`pihole/`](pihole/) | Network-wide ad blocking at the DNS layer | DNS resolution end to end, recursive vs. authoritative servers, caching/TTLs, DHCP, limits of DNS blocking (DoH, hardcoded DNS) | In progress: installed, one device filtered |
| 2 | [`personal_website/`](personal_website/) | A personal website, self-hosted on the Pi | Web servers, reverse proxies, ports/sockets, HTTP/HTTPS, TLS certificates, DNS records, NAT/port forwarding vs. tunnels, dynamic IPs, internet exposure | In progress: placeholder served on the LAN |
| 3 | [`media_suite/`](media_suite/) | Local web UI to browse and play movies and games stored on the Pi | Service discovery on the LAN, storage and permissions, streaming vs. transcoding, the Pi's hardware limits, browser playback and emulation | Working: qBittorrent + search plugins download to the USB drive, Jellyfin plays them on the LAN; games not started |

All three sit on top of a shared foundation in [`base/`](base/): OS install,
SSH, a fixed IP address, updates, users/permissions, and the firewall. That's
set up first, because every service depends on it.

---

## Big picture

```
                         Internet
                             │
                  (mobile carrier's CGNAT, probably)
                             │  5G/4G radio link
                    ┌────────┴────────┐
                    │ Brovi H158-381  │  ← 5G router: NAT, Wi-Fi, and DHCP (hands out
                    │ 192.168.8.1     │    IPs and the DNS server address)
                    └────────┬────────┘
                             │  home LAN (Ethernet)
         ┌───────────────────┼────────────────────────┐
         │                   │                        │
   Laptops/phones      Raspberry Pi 4            Other devices
         │             ┌───────────────┐
         │  DNS :53 ──►│ Pi-hole       │──► upstream DNS resolver
         │  HTTP/S ───►│ Web server    │◄── (later) internet visitors via port forward or tunnel
         │  HTTP ─────►│ qBittorrent   │──► USB HDD (/mnt/media) ◄── torrent peers (outbound)
         │  HTTP ─────►│ Jellyfin      │◄── reads the films and shows from the USB HDD
                       └───────────────┘
```

Each sub-project README has its own, more detailed flow diagram.

---

## Hardware

| Role | Item | Notes |
|---|---|---|
| Computer | Raspberry Pi 4 Model B, 4 GB RAM | Enough for all three services; weak at real-time video transcoding |
| OS storage | SanDisk High Endurance 64 GB microSD | Endurance-rated for 24/7 writes; may later move the OS to SSD |
| Power | Official Raspberry Pi 15 W USB-C (5.1 V / 3 A) | Under-spec supplies cause undervoltage → instability and SD corruption |
| Case / cooling | Argon NEO heatsink case | Passive cooling; the metal case weakens Wi-Fi, which is fine since we use Ethernet |
| Media storage | Maxone 500 GB 2.5″ USB 3.0 HDD | Bus-powered; plug into a blue USB 3 port. Likely SMR: fine for read-heavy media |
| Network | Cat6 Ethernet cable (+ spare) | Wired on purpose: a DNS server should not depend on Wi-Fi |
| Flashing | USB 3.0 / USB-C SD card reader | For writing the OS image from a laptop |

**Software / network environment** (fill in as decided):

- OS: **Raspberry Pi OS Lite (64-bit)**, Debian-based, headless. First-boot
  configuration (hostname, user, SSH key) is applied by cloud-init from the SD
  card's `bootfs` partition. See [`base/README.md`](base/README.md).
- Network edge: **Brovi H158-381**, a 5G/4G cellular router (SIM-based, Huawei-family
  hardware). No separate router behind it. Factory LAN defaults: router at
  `192.168.8.1`, subnet `192.168.8.0/24`.
- Public IPv4 or CGNAT: **probably CGNAT** (the norm for cellular broadband), not yet
  verified. To check, compare the WAN IP on the router's admin page with the output
  of `curl -4 ifconfig.me`; if they differ, or the WAN IP is in `100.64.0.0/10`,
  it's CGNAT. If so, sub-project 2 is reached through a tunnel (or IPv6) instead of
  port forwarding.
- Router admin credentials, Wi-Fi name/password, IMEI, serial number: **never in
  this repo**. They're on the router's label and in my password manager.

Personal network details (IP ranges, hostnames, domain) live in gitignored
files. See [Secrets](#secrets-and-personal-details).

---

## Repo layout

```
.
├── README.md          ← you are here: overview, hardware, conventions
├── .gitignore         ← keeps secrets and personal details out of git
├── docs/
│   ├── NOTES.md       ← concepts learned, written in my own words
│   └── rebuild.md     ← fresh-install-to-working-server checklist
├── base/              ← OS install, SSH, static IP, updates, firewall
├── pihole/            ← sub-project 1
├── personal_website/  ← sub-project 2
└── media_suite/       ← sub-project 3
```

**Why one repo instead of several:** the three services share one machine, one
network, and one base configuration. Changes often cross boundaries (e.g. a
firewall rule for the web server, or a DNS record in Pi-hole for the media
server). A single repo keeps those changes in one history.

Every sub-project folder has its own `README.md` with the same sections:

1. **What it is**
2. **How it works**, with a data/network flow diagram
3. **Setup from scratch**, as step-by-step instructions with the reasoning attached to each step
4. **How to verify**: commands that show it working, not just "it seems fine"
5. **Failure modes and troubleshooting**: symptoms, which logs/tools to check, how to recover

---

## Conventions

### Configs, scripts, and code
- Comments explain **why**, not just what. Write for a future me who has forgotten everything.
- Clear and explicit beats clever and terse.
- Shell scripts start with `set -euo pipefail`, use meaningful variable names,
  and have a header comment describing purpose, inputs, and side effects.

### Secrets and personal details
- **Never commit secrets.** Passwords, API keys, private keys, tokens, and
  personal network details go in files listed in `.gitignore`.
- For every ignored file, commit an `.example` template showing the structure
  (e.g. `pihole/.env.example` next to the real, ignored `pihole/.env`).
- **Before every push:** run `git status` and `git diff --staged` and check what's
  actually going out.

### Git
- Small, focused commits, one logical change each.
- Commit messages say what changed and why, e.g. `pihole: set upstream to Quad9 for DNSSEC support`.
- Experiments go on branches (`git switch -c experiment/unbound`) and merge back only once understood.

---

## Current status

- **base/**: done apart from a router config backup and a CGNAT check. OS
  flashed and updated, key-only SSH, address pinned by a router DHCP reservation,
  `ufw` firewall active (LAN-only). The snags from the first build (WSL2 +
  Imager, cloud-init's once-per-instance rule) are written up in
  [`base/README.md`](base/README.md#5-failure-modes-and-troubleshooting).
- **pihole/**: installed and verified. **One device (the laptop) is filtered**;
  network-wide filtering is blocked by the router, which cannot override DNS for
  its SIM connection. Pi-hole as DHCP server is the remaining option, deferred.
  Details, snags and the router findings are in [`pihole/README.md`](pihole/README.md).
- **personal_website/**: nginx serves a placeholder page on the LAN, deployed
  from the repo with `rsync`. Pi-hole's admin UI moved to `:8080` to free ports
  80/443. Not reachable from outside the LAN yet; the CGNAT check and the access
  decision are next. See [`personal_website/README.md`](personal_website/README.md).
- **media_suite/**: **up and running, and working well.** The USB drive is
  mounted at `/mnt/media` at boot (exFAT, via `/etc/fstab`). qBittorrent
  (`:8081`) with search plugins downloads into `movies/` or `series/` by
  category, and Jellyfin (`:8096`) serves both libraries to the LAN. Day-to-day
  workflow, naming rules and setup are in
  [`media_suite/README.md`](media_suite/README.md). Games are not started.
  Reachable from outside the home for me and invited friends through
  [Tailscale](#remote-access-tailscale), with nothing exposed publicly.

---

## Remote access: Tailscale

### What it is

Tailscale is a mesh VPN: every device runs a small client, and the clients
build encrypted WireGuard connections straight to each other. It lets me, and
friends I invite, use Jellyfin from anywhere **without opening anything to the
public internet**.

Why this instead of a public `media.<domain>` address: the Pi is behind the
carrier's CGNAT (no port forwarding possible), Jellyfin is not hardened enough
to face the whole internet on its own, and a public login page in front of a
torrented library is a risk I don't need. Tailscale only lets in devices I have
approved.

| | |
|---|---|
| Client | `tailscale` 1.104.2, from Tailscale's own apt repository (`pkgs.tailscale.com`, Debian trixie) |
| Service | `tailscaled`, enabled at boot |
| Pi's name / address | `raspberry-alpha`, `100.70.101.102` (stays the same unless the Pi is removed from the tailnet) |
| Tailnet owner | my personal account. Friends use **their own** accounts, and only the Pi is shared with them |
| Key expiry | **disabled** for the Pi (see failure mode 3) |
| Friends can reach | Jellyfin, `tcp:8096`, only |

### How it works

```
  my phone / laptop                 friend's phone / laptop / TV stick
  (my tailnet, my account)          (their tailnet, their own account)
         │                                    │   accepted my share of the Pi
         │   WireGuard, end-to-end encrypted  │
         └────────────────┬───────────────────┘
                          │  The Pi only ever connects OUT (to Tailscale's
                          │  coordination server and to peers), which is why
                          │  CGNAT doesn't matter. If no direct path can be
                          │  punched, traffic goes via a Tailscale relay (DERP).
                          ▼
              tailscale0 on the Pi (100.70.101.102)
                          │  access policy (in the admin console):
                          │    me      → every port on every device
                          │    friends → tcp:8096 on the Pi, nothing else
                          ▼
                    Jellyfin :8096
```

- **Sharing is one-way.** A shared Pi appears in my friends' tailnets, but they
  never see my other devices, and the Pi cannot start connections to theirs.
- **The policy is the firewall, not ufw.** Tailscale installs its own netfilter
  rules for traffic arriving on `tailscale0`, so my LAN-only ufw rules don't
  decide what friends can reach. The policy in the admin console does.
- **It runs inside the CyberGhost VPN.** The VPN routes all the Pi's internet
  traffic through `tun0` (`ip route` shows `0.0.0.0/1` and `128.0.0.0/1 via ...
  dev tun0`), Tailscale's included. It still works because Tailscale only needs
  outbound connections, but every remote stream takes the extra trip through
  the VPN server.
- **Jellyfin sees Tailscale clients as remote.** `100.x` addresses aren't in
  Jellyfin's LAN ranges, so per-user *Internet streaming bitrate limits* apply
  to them. That protects the 5G upload, which every remote viewer shares.

### Setup from scratch

1. **Add Tailscale's apt repository and install.** Their signing key and source
   list, then the package. Using the repository (rather than a one-off
   download) means `apt upgrade` keeps it patched.

   ```bash
   curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
   curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
   sudo apt update && sudo apt install tailscale
   ```

2. **Join the Pi to my tailnet.** `sudo tailscale up` (no flags) prints a login
   URL. Open it on the laptop and sign in with my account. The Pi then shows up
   in the admin console at `login.tailscale.com` and gets its `100.x` address.
   Install the app on my phone and sign in with the same account.

3. **Disable key expiry for the Pi.** Admin console → **Machines** →
   `raspberry-alpha` → **⋯** → **Disable key expiry**. Otherwise the Pi's key
   expires after about 180 days, and everyone loses access until I log in on
   the Pi again.

4. **Replace the default allow-everything policy, before sharing.** Admin
   console → **Access controls**. The default grant
   `{"src": ["*"], "dst": ["*"], "ip": ["*"]}` lets anyone with access to the
   Pi reach every port, SSH and the qBittorrent and Pi-hole admin pages
   included. The policy I use:

   ```jsonc
   {
   	// Names for Tailscale IPs, so rules read as "pi" instead of a bare address.
   	"hosts": {
   		"pi": "100.70.101.102",
   	},

   	"grants": [
   		// Me (members of this tailnet): every device, every port.
   		{"src": ["autogroup:member"], "dst": ["*"], "ip": ["*"]},

   		// Friends who accepted a share of the Pi: Jellyfin only. No SSH (22),
   		// Pi-hole (53, 8080, 8443) or qBittorrent (8081). Anything not listed
   		// here is denied.
   		{"src": ["autogroup:shared"], "dst": ["pi"], "ip": ["tcp:8096"]},
   	],

   	// Tailscale SSH: only me, only into my own devices (the default).
   	"ssh": [
   		{
   			"action": "check",
   			"src":    ["autogroup:member"],
   			"dst":    ["autogroup:self"],
   			"users":  ["autogroup:nonroot", "root"],
   		},
   	],

   	// Checked on every save. Use a real friend's login.
   	// "tests": [
   	// 	{
   	// 		"src":    "<friend-login>",
   	// 		"accept": ["pi:8096"],
   	// 		"deny":   ["pi:22", "pi:8080", "pi:8081"],
   	// 	},
   	// ],
   }
   ```

   Before saving, the **Preview rules** tab should still show my own account
   with full access, so I can't lock myself out.

5. **Share the Pi, one invite per friend.** **Machines** → `raspberry-alpha` →
   **⋯** → **Share** → copy the invite link. A separate link per person means
   I can revoke one friend without affecting the others.

6. **What each friend does:** install Tailscale on each device they watch on,
   sign in with their own account, open the invite link, then point the
   Jellyfin app (or a browser) at `http://100.70.101.102:8096`.

7. **A Jellyfin account per friend**, created in Jellyfin's Dashboard →
   **Users** → **+**:
   - **"Allow this user to manage the server" unticked.** Admin in Jellyfin
     means installing plugins, which run as code on the Pi, and the Tailscale
     policy can't help because the admin dashboard is on 8096 too.
   - No media deletion.
   - **Internet streaming bitrate limit** about 4–8 Mbps, so a few remote
     viewers fit in the 5G upload.

### How to verify

| What | Command / action | Expected |
|---|---|---|
| Service running | `systemctl is-active tailscaled` and `systemctl is-enabled tailscaled` | `active`, `enabled` |
| Pi is on the tailnet | `tailscale status` | `raspberry-alpha` and my devices. Friends' devices that accepted the share show up as `device-of-shared-to-user` |
| Pi's address | `tailscale ip -4` | `100.70.101.102` |
| Key expiry off | Admin console → Machines | `raspberry-alpha` shows **Expiry disabled** |
| Friends limited to Jellyfin | From a friend's device: open `http://100.70.101.102:8096`, then `:8080/admin` and `:8081` | Jellyfin loads; the other two **time out** |
| Sharing is one-way | On the Pi: `tailscale ping <friend-device-ip>` | Times out: the Pi can't reach their devices |
| Nobody else is a Jellyfin admin | Create an API key (Dashboard → **API Keys**), run the command below on the Pi, then **delete the key** | Only my own account prints `ADMIN` |

```bash
curl -s -H 'Authorization: MediaBrowser Token="<key>"' http://localhost:8096/Users | python3 -c "import json,sys; [print(u['Name'], 'ADMIN' if u['Policy']['IsAdministrator'] else '-') for u in json.load(sys.stdin)]"
```

### Failure modes and troubleshooting

| # | Symptom | Cause | How to check | Fix |
|---|---|---|---|---|
| 1 | The admin check above fails with `JSONDecodeError: Expecting value: line 1 column 1`. **Hit on this build** | Jellyfin 12.2 rejects the old `X-Emby-Token` header with `401` and an empty body, which Python can't parse | `curl -s -o /dev/null -w '%{http_code}\n' -H ... http://localhost:8096/Users` prints `401` | Use `Authorization: MediaBrowser Token="<key>"`, as in the command above |
| 2 | Same error after pasting the real key. **Hit on this build** | Typed `$<key>` instead of `<key>`. The shell read `$1` as an (empty) variable, so the key lost its first character | `echo "$10198..."` shows the key with its first character missing | Paste the key with no `$`. The `$` only belongs in front of a variable name, e.g. `$JF_KEY` |
| 3 | Nobody can reach the Pi over Tailscale, though it's fine on the LAN | The Pi's node key expired (default about 180 days) | Admin console shows the Pi as **Expired**; `tailscale status` on the Pi asks to log in | Avoided by disabling key expiry (step 3). If it happens: `sudo tailscale up`, then log in again |
| 4 | A friend can open SSH, Pi-hole's or qBittorrent's page | The default allow-everything grant is still in the policy, and ufw doesn't filter `tailscale0` | Preview rules for the friend's login in Access controls | The policy in step 4 |
| 5 | Remote playback buffers, though it's fine at home | The 5G upload is shared by every remote viewer; a relayed (DERP) path adds latency; or the Pi is transcoding | `tailscale ping <device-ip>` says `via DERP(...)` (relayed) or `via <ip>:<port>` (direct). Jellyfin Dashboard → Activity shows **Transcoding** | Lower the user's bitrate limit; prefer H.264 files |
| 6 | A friend's smart TV can't connect | Most Samsung/LG TVs and Rokus have no Tailscale app | | A streaming stick (Android TV / Google TV, Apple TV) with Tailscale, or cast from a phone |
| 7 | The Pi's own DNS lookups changed: `/etc/resolv.conf` now says `generated by tailscale` and `nameserver 100.100.100.100` | `tailscale up` turns on "accept DNS" by default, and Tailscale manages the Pi's resolver (MagicDNS). Pi-hole's service to the LAN is unaffected | `head -5 /etc/resolv.conf` | Expected. To give the Pi back its old resolver: `sudo tailscale set --accept-dns=false`. **Open question:** whether this sends the Pi's own lookups, torrent trackers included, outside the CyberGhost VPN's DNS |

---

## Quick reference

### Services and ports

What is listening on the Pi (`192.168.8.51`), checked with `sudo ss -tulpn`.

| Service | Port | Protocol | Used for |
|---|---|---|---|
| SSH (base) | 22 | TCP | Logging in from the laptop |
| Pi-hole | 53 | TCP + UDP | DNS queries from LAN devices |
| Pi-hole | 8080 | TCP | Admin web UI: `http://192.168.8.51:8080/admin` |
| Pi-hole | 8443 | TCP | Admin web UI over HTTPS |
| Website (nginx) | 80 | TCP | The site over HTTP: `http://192.168.8.51/` |
| Website (nginx) | 443 | TCP | Reserved for HTTPS; nothing listening until TLS is set up |
| qBittorrent | 8081 | TCP | Web UI: `http://192.168.8.51:8081` (qBittorrent's default is 8080, which Pi-hole already uses) |
| qBittorrent | 24950 | TCP + UDP | Incoming connections from torrent peers |
| qBittorrent | 6771 | UDP | Local peer discovery (finding peers on the LAN) |
| Jellyfin | 8096 | TCP | Web UI and streaming: `http://192.168.8.51:8096` |
| Jellyfin | 7359 | UDP | Lets Jellyfin apps (TV, phone) find the server on the LAN |
| Tailscale | 41641 | UDP | WireGuard traffic to and from other Tailscale devices. Jellyfin over Tailscale: `http://100.70.101.102:8096` |

### Common commands

A running list of commands I use on the Pi. Append new ones at the bottom.

- `ssh doodlster@192.168.8.51` (from the laptop): log in to the Pi.
- `lsblk`: storage drives and their partitions, sizes, and mount points.
- `lsusb`: devices connected over USB.
- `sudo ss -tulpn`: every port the Pi is listening on (TCP and UDP) and the
  program holding it. `sudo` is needed to see the program name for services
  that run as root, like nginx and Pi-hole.
- `sudo ufw status`: list the firewall rules. Shows which ports are actually
  let in from outside, and from where (`ss` only shows what is listening).
- `sudo ufw status numbered`: the same list with a number on each rule, for
  removing one with `sudo ufw delete <number>`.
- `curl -LO <url>`: download a file from a website into the current folder,
  keeping its original name. `-L` follows redirects (download links often
  bounce to another server first); `-O` saves it under the name in the URL.
  Use `-o <name>` instead to pick the name. `cd` to where it should go first,
  e.g. `cd /mnt/media` for anything big.
- `sha256sum <file>`: fingerprint of a downloaded file. Compare it with the
  checksum published on the download page; if they differ, the file is
  corrupted or not the real one.
- **Install scripts: download, read, then run.** Never pipe a script straight
  into a shell (`curl ... | sudo bash`). Instead:
  `curl -sSL <url> -o install.sh`, then `less install.sh`, then
  `sudo bash install.sh`. Same pattern as the Pi-hole install.
- `systemctl is-active openvpn-client@cyberghost`: whether the CyberGhost VPN
  is running (`active`) or not (`inactive`).
- `curl -s https://ipinfo.io/org`: who the Pi's internet traffic appears to
  come from. A hosting company (e.g. `M247`) means it is going through the
  VPN; my ISP's name means it is not.
- `tailscale status`: devices the Pi can see on Tailscale, mine and friends'
  shared-in ones, with their `100.x` addresses.
- `tailscale ping <100.x-ip>`: whether a Tailscale device is reachable, and
  whether the path is direct or through a relay (`via DERP`).

---

## Getting started

1. Read [`docs/rebuild.md`](docs/rebuild.md) for the full build order.
2. Set up [`base/`](base/) first: OS, SSH, fixed IP, firewall.
3. Then the sub-projects in order: `pihole/` → `personal_website/` → `media_suite/`.

---

## References

- Raspberry Pi documentation: https://www.raspberrypi.com/documentation/
- Pi-hole documentation: https://docs.pi-hole.net/
- Tailscale documentation (sharing, access policies): https://tailscale.com/kb/
- Man pages on the Pi itself: `man <command>`, `man 5 <config-file>` for file formats

