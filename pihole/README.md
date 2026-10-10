# pihole: network ad blocking at the DNS layer

**Status:** installed natively on the Pi and verified. **One device (the laptop)
is filtered**, by setting its DNS by hand. Network-wide filtering is **not**
done: the router has no setting that makes it possible (see
[Router limits](#router-limits)). Pi-hole as DHCP server is deferred.

Personal details are placeholders here: `<pi-ip>`, `<lan-cidr>` (the home subnet),
`<pi-ula-ipv6>` (the Pi's private IPv6 address), `<lan-ula-cidr>` (the router's
private IPv6 prefix). Real values are not in this repo.

---

## 1. What it is

A DNS server on the Pi that answers "what is the IP for `example.com`?" for the
devices pointed at it. If the name is on a blocklist, it answers `0.0.0.0` (or
`::` for IPv6) instead, so the ad or tracker never loads. Everything else is
forwarded to an upstream resolver and cached.

| | |
|---|---|
| Version | Pi-hole core v6.4.3, web v6.6 (v6 has the web server built into FTL) |
| Install | Native, from the official installer (not Docker; see below) |
| Upstream | Quad9 (filtered, DNSSEC): `9.9.9.9`, `149.112.112.112` |
| Blocklist | StevenBlack unified hosts, ~72.5k domains |
| Query log | On, privacy level 0 ("show everything"): my own network, and per-domain visibility is the point |
| Admin UI | `http://<pi-ip>:8080/admin`: moved off 80/443 so the website can have the default web ports (see [3.4](#34-move-the-admin-ui-off-ports-80443)) |

Why native, not Docker: the goal is understanding, and Docker adds a layer
(networking modes, volumes) between me and the thing I am trying to learn. Pi-hole
is officially supported on Raspberry Pi OS / Debian.

Why a public forwarder first (Quad9) instead of Unbound: change one variable at a
time. Forwarding vs. recursive resolution is a planned comparison on a branch
(`experiment/unbound`).

---

## 2. How it works

```
 device ──DNS :53──►  Pi-hole (FTL)
                        │
                        ├─ name on a blocklist?  → answer 0.0.0.0 / ::  (TTL 2), stop
                        ├─ in cache?             → answer from memory (TTL counts down)
                        └─ else                  → forward to Quad9 ─► answer, cache it
```

Things observed on this install:

- **Blocked names get a null answer in both families**: `A 0.0.0.0` and
  `AAAA ::`. Modern browsers also ask for `HTTPS` (type 65) records, and those
  are blocked too.
- **The cache is visible**: the same query 3 s apart returned TTL 135, then 132.
- **DNSSEC is validated by Quad9, not by Pi-hole.** The reply's `AD` flag is not
  set at the client, but a deliberately broken domain (`dnssec-failed.org`)
  returns `SERVFAIL`, which only happens if something is validating.
- **A blocked name is not "an error"**: the client gets a valid answer pointing
  nowhere and the connection fails at once, which is why blocking is fast.

### Limits of DNS blocking (the point of the exercise)

Blocking is by *name*, and only for clients that ask this server. Things that skip
it: browser DNS-over-HTTPS ("Secure DNS", also active in private windows), VPNs and
Private Relay, apps and TVs with a hardcoded resolver, and a competing IPv6 DNS
server advertised by the router (see snag 2 below).

---

## 3. Setup from scratch

Prerequisites, from [`base/`](../base/README.md): a fixed address for the Pi
(router reservation) and an active firewall. Pi-hole will be the DNS server, so
its address must not change.

### 3.1 Firewall rules (LAN only)

```bash
sudo ufw allow from <lan-cidr> to any port 53  comment 'DNS (tcp+udp) from LAN'
sudo ufw allow from <lan-cidr> to any port 8080 proto tcp comment 'Pi-hole admin UI'
sudo ufw allow from <lan-cidr> to any port 8443 proto tcp comment 'Pi-hole admin UI (TLS)'
# IPv4 sources do not match IPv6 traffic. Needed for clients using the IPv6 server:
sudo ufw allow from <lan-ula-cidr> to any port 53 comment 'DNS (v6 ULA) from LAN'
```

FTL listens on `0.0.0.0:53` and `[::]:53`, so the firewall is the only thing
deciding who can use it.

### 3.2 Install (read it first, it runs as root)

```bash
cd ~
curl -sSL https://install.pi-hole.net -o pihole-install.sh
less pihole-install.sh          # skim; q to quit
sudo bash pihole-install.sh
```

| Prompt | Choice | Why |
|---|---|---|
| Static IP notice | OK | The reservation covers it |
| Upstream DNS | Quad9 (filtered, DNSSEC) | Validates DNSSEC, blocks known-malicious domains |
| Blocklist | default (StevenBlack) | Reasonable start; tune after seeing real traffic |
| Admin web interface | yes | Needed for the query log |
| Firewall / "open ports" (if offered) | **No** | It would open ports to everyone; the rules above are narrower |
| Query logging | yes | The log is the learning tool |
| Privacy level | 0, show everything | Own network |

The installer prints a **random admin password once**. Set your own straight
away and keep it out of the repo and out of chat:

```bash
sudo pihole setpassword
```

### 3.3 Point a client at it (per device)

Windows 11: *Settings → Network & internet → Wi-Fi → (network) → DNS server
assignment → Edit → Manual*.

| Field | Value |
|---|---|
| IPv4 | on, preferred `<pi-ip>`, alternate **empty** |
| IPv6 | on, preferred `<pi-ula-ipv6>`, alternate **empty** |
| DNS over HTTPS | off (Pi-hole does not speak DoH; Windows may silently fall back) |

**Both families must be set.** Windows asks the IPv6 server first, and the
router advertises its own over IPv6, so setting only IPv4 leaves most queries
bypassing Pi-hole (snag 2). Use the private (ULA) IPv6 address, not a public
`2001:…` one: the carrier rotates the public prefix.

Other devices: same idea in their Wi-Fi settings, one by one, until a
network-wide option exists.

### 3.4 Move the admin UI off ports 80/443

Only one program can listen on a given port. The installer puts the admin UI on
80/443, which are the ports browsers assume, so they are what the website
([`personal_website/`](../personal_website/)) should have. The admin UI is only
for me, so it takes the odd ones. Do this with the 8080/8443 firewall rules from
3.1 already in place, so the page stays reachable.

```bash
sudo pihole-FTL --config webserver.port    # before: 80o,443os,[::]:80o,[::]:443os
sudo pihole-FTL --config webserver.port '8080o,[::]:8080o,8443os,[::]:8443os'
sudo systemctl restart pihole-FTL          # DNS drops for a couple of seconds
```

The value is a list of listeners: a port, optionally prefixed with an address
(`[::]` is all IPv6), and suffixed with `o` (optional: do not fail if that address
family is unavailable) and `s` (TLS). FTL re-bound its web server in place when
the setting changed (same process ID), and DNS kept answering.

Undo: set the value back to the "before" string above and restart.

---

## 4. How to verify

`dig` is not installed in WSL here. `nslookup` and PowerShell work without it.

| Check | Command | Expect |
|---|---|---|
| Resolves | `nslookup example.com <pi-ip>` | real addresses |
| Blocks | `nslookup doubleclick.net <pi-ip>` | `0.0.0.0` (and `::`) |
| Cache | the same query twice, a few seconds apart | TTL decreasing |
| DNSSEC upstream | `nslookup dnssec-failed.org <pi-ip>` | `SERVFAIL` |
| Web UI up | `curl -s -o /dev/null -w '%{http_code}\n' http://<pi-ip>:8080/admin/` | `302` (redirect to login) |
| Web ports free | `sudo ss -tlpn \| grep -E ':(80\|443)\b'` (Pi) | no output until the website's server starts |
| Service | `systemctl is-active pihole-FTL` (Pi) | `active` |
| **The client really uses it** (laptop, PowerShell) | `Resolve-DnsName <fresh-blocked-name> -Type A -DnsOnly` | `0.0.0.0` |
| Which DNS is the client using | `ipconfig /all` | only the Pi's IPv4 and IPv6 |
| Live traffic | Admin UI → Query Log, browse a news site | your device's lookups, trackers in red |

The "client really uses it" row is the one that matters. Asking the Pi directly
(`nslookup … <pi-ip>`) proves Pi-hole works, not that the device uses it. Use a
name that device has not looked up recently, because the OS caches answers.

---

## 5. Failure modes and troubleshooting

### Router limits

The router is a Brovi H158-381 (a 5G/4G cellular router). Findings, in the order
I hit them:

| Where | What is there | Consequence |
|---|---|---|
| *Network settings → Ethernet → Ethernet Settings* | "Set DNS server manually", primary/secondary | Applies to the **Ethernet WAN** only (a wired uplink). My internet comes over the SIM, so it has no effect. Left set to the Pi; harmless. |
| *Network settings → Mobile Network → Internet Connection* | Mobile data, roaming, auto-select, MTU | **No DNS field.** The router will not let me override DNS for the SIM connection. |
| *DHCP page* | DHCP server **on/off toggle**, range, lease time, IP↔MAC binding list | Pi-hole as DHCP server is *possible* (deferred, below). |
| Router's IPv6 settings | **not checked yet** | Decides whether DHCP-based filtering could be complete (see Deferred). |

The router acts as a **DNS proxy**: devices are told `192.168.8.1` (and its IPv6
link-local address) and the router forwards to the carrier. That is why nothing on
the Pi can filter the network without a device-side or DHCP-side change.

### Snags

| # | Symptom | Cause | How to confirm | Fix |
|---|---|---|---|---|
| 1 | Set the router's "DNS server manually" to the Pi, but blocked names still resolve | The setting was on the Ethernet WAN page; traffic goes via the SIM | Query the router directly: `nslookup doubleclick.net 192.168.8.1` returns a real IP. The page's value persisted after reload, so it was saved, just not used | No router-side fix exists. Per-device DNS instead |
| 2 | Laptop DNS set to the Pi (IPv4 only), query log shows some lookups, but ads still load | **IPv6 DNS leak.** Windows' DNS list was `[router IPv6, Pi, router IPv6]`; it asks the first entry, which is the router | `ipconfig /all` shows the router's `fe80::…` address first; `Resolve-DnsName <blocked>` returns real IPs while a direct query to the Pi returns `0.0.0.0` | Set the IPv6 DNS manually to the Pi's ULA address too, and add the IPv6 firewall rule |
| 3 | After setting IPv6 DNS, queries to the Pi time out | The firewall rules had `from <lan-cidr>` (IPv4); IPv6 sources did not match, so they were dropped | `ufw status` has no IPv6 allow for 53 | `ufw allow from <lan-ula-cidr> to any port 53` |
| 4 | `nslookup` on the Pi itself returns real IPs | The Pi's own resolver is the router (`/etc/resolv.conf` from DHCP), not Pi-hole | `grep nameserver /etc/resolv.conf` | **Intentional, leave it.** If Pi-hole breaks, the Pi can still resolve names to repair it. Test Pi-hole from the Pi with `nslookup <name> 127.0.0.1` |
| 5 | Query log is empty while browsing | Browser "Secure DNS" (DoH) bypasses the system resolver, in private windows too | Browser settings → privacy → secure DNS | Turn it off, or use the system resolver |
| 6 | Tests run from WSL show as the laptop in the query log | WSL2 is NAT'd by Windows | Log client address is the laptop's | Not a fault. Test from PowerShell when the *device's* behaviour matters |
| 7 | "I used a blocked name and it still resolved" | The OS (or browser) cached an earlier answer | `Resolve-DnsName` returns the same IP with a TTL counting down | Use a name not looked up before, or flush: `ipconfig /flushdns` (may need an elevated prompt) |

### Recovery

Pi-hole is only in the path for devices explicitly pointed at it. To stop using
it on the laptop: DNS server assignment back to **Automatic**. Nothing on the
router was changed that would need undoing.

### Security notes

- Admin UI and DNS are reachable from the LAN only (firewall).
- The installer's generated admin password is shown once in a terminal. Change it
  immediately (`pihole setpassword`) and never paste it anywhere.
- Pi-hole's settings export (Teleporter) can contain the password hash: do not
  commit one.

---

## Deferred: Pi-hole as the DHCP server

Not started, on purpose. The idea: turn the router's DHCP server off and have
Pi-hole hand out leases that name Pi-hole as the DNS server, so every device is
covered without per-device settings, and the log shows each device by name.

What is known:

- The router's DHCP server **can** be switched off (confirmed on the DHCP page).
- IPv6 is the hard part. Pi-hole's DHCP hands out IPv4 leases; v6 also has an
  option for IPv6 (SLAAC + router advertisements), but the router would keep
  sending its **own** router advertisements naming itself as the IPv6 DNS server,
  which is exactly the leak in snag 2. Two competing advertisers is a mess, so
  coverage is only clean if the router can **disable IPv6 on the LAN side**.
  Unchecked. (Pi-hole's IPv6 option was not tried.)
- If the Pi is down, nothing gets a new lease, and existing leases expire (1 day
  now). That is a bigger failure than "DNS is down".
- The Pi needs a **static address on itself** first: today it uses DHCP from the
  router (`ipv4.method auto` in NetworkManager), so it would have no address
  after a reboot once the router's DHCP is off.
- A DHCP request has source `0.0.0.0`, so the firewall needs its own rule
  (UDP 67 in); the existing LAN-sourced rules would not match.
- Needs a rehearsed recovery first: prove the router's admin page is reachable
  from the laptop with a manual static IP *before* switching anything off, and
  take a config backup (System → Backup & Restore).

Phases if it goes ahead (on a branch, `experiment/pihole-dhcp`): look at the
router for an IPv6 switch → static IP on the Pi → rehearse recovery → configure
Pi-hole DHCP disabled → cutover (router DHCP off, Pi-hole DHCP on, back to back)
→ verify with a lease renewal → handle IPv6 → document.

---

## Status

- [x] Firewall rules for DNS and the admin UI (LAN only, IPv4 and IPv6)
- [x] Pi-hole v6 installed natively; upstream Quad9; blocklist StevenBlack
- [x] Admin password changed from the generated one
- [x] Blocking, caching, and DNSSEC behaviour verified directly against the Pi
- [x] One client (laptop) filtered, IPv4 and IPv6, verified through the OS resolver
- [x] Admin UI moved to 8080/8443; `ss` shows FTL there and nothing on 80/443; DNS still resolves
- [ ] Admin UI loads at `:8080/admin` in a browser, and the port setting survives `systemctl restart pihole-FTL`
- [x] Router limits investigated and written up
- [ ] Browser "Secure DNS" checked on the laptop's browsers
- [ ] Other devices (phone, TV): per-device DNS, or wait for the DHCP experiment
- [ ] Blocklist tuning after a few days of real traffic (false positives, extra lists)
- [ ] `experiment/unbound`: recursive resolver instead of forwarding to Quad9
- [ ] `experiment/pihole-dhcp`: see Deferred
- [ ] Router config backup (before any DHCP change)
