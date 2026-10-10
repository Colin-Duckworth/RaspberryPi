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
| 1 | [`pihole/`](pihole/) | Network-wide ad blocking at the DNS layer | DNS resolution end to end, recursive vs. authoritative servers, caching/TTLs, DHCP, limits of DNS blocking (DoH, hardcoded DNS) | Not started |
| 2 | [`website/`](website/) | A personal website, self-hosted on the Pi | Web servers, reverse proxies, ports/sockets, HTTP/HTTPS, TLS certificates, DNS records, NAT/port forwarding vs. tunnels, dynamic IPs, internet exposure | Not started |
| 3 | [`media/`](media/) | Local web UI to browse and play movies and games stored on the Pi | Service discovery on the LAN, storage and permissions, streaming vs. transcoding, the Pi's hardware limits, browser playback and emulation | Not started |

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
         │  HTTP ─────►│ Media server  │──► USB HDD (/mnt/media)
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
├── website/           ← sub-project 2
└── media/             ← sub-project 3
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

- **base/**: OS flashed, first-boot config applied, key-only SSH works.
  Still to do: updates, fixed IP, firewall. The snags from the first build
  (WSL2 + Imager, cloud-init's once-per-instance rule) are written up in
  [`base/README.md`](base/README.md#5-failure-modes-and-troubleshooting).
- **pihole/, website, media**: not started.

---

## Getting started

1. Read [`docs/rebuild.md`](docs/rebuild.md) for the full build order.
2. Set up [`base/`](base/) first: OS, SSH, fixed IP, firewall.
3. Then the sub-projects in order: `pihole/` → `website/` → `media/`.

---

## References

- Raspberry Pi documentation: https://www.raspberrypi.com/documentation/
- Pi-hole documentation: https://docs.pi-hole.net/
- Man pages on the Pi itself: `man <command>`, `man 5 <config-file>` for file formats