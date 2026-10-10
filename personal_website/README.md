# personal_website: a static site served by nginx on the Pi

**Status:** nginx is installed and serving on the **LAN only**, deployed from
this repo with one command. The site is a two-page portfolio **template**
(home and projects, plus a 404 page) with every personal value left as a
visible `[[PLACEHOLDER]]`; how to fill it in is in [`EDITING.md`](EDITING.md).
No public name, no TLS, and not reachable from outside the home network. Those
are deliberate later steps (see [Deferred](#deferred)).

Personal details are placeholders here: `<pi-ip>`, `<pi-user>`, `<lan-cidr>`.
Real values live in the git-ignored `base/pi.env`.

---

## 1. What it is

A web server on the Pi that hands out the files in `site/` to any browser that
asks. Developing happens on the laptop, in this repo; the Pi only receives the
result.

| | |
|---|---|
| Server | nginx (Debian package), plain HTTP on port 80 |
| Site type | Static files only: no database, no application server, nothing to run besides nginx |
| Source | [`site/`](site/): this folder is exactly what gets published. How to edit it: [`EDITING.md`](EDITING.md) |
| Server config | [`nginx/personal_website.conf`](nginx/personal_website.conf) |
| Deploy | [`scripts/deploy.sh`](scripts/deploy.sh): `rsync` over SSH |
| On the Pi | web root `/var/www/personal_website`, config `/etc/nginx/sites-available/personal_website` |
| Address | `http://<pi-ip>/` from the LAN |

Why static: the least that can go wrong and the least to keep patched. The
networking things I want to learn (ports, HTTP, TLS, DNS names, exposure) are
the same for a static site and a dynamic one.

Why nginx rather than Apache or Caddy: small, common, and the same server will
later sit in front of the media suite as a reverse proxy.

---

## 2. How it works

```
 laptop                                        Pi
 ──────                                        ──
 edit site/index.html
 scripts/deploy.sh ──rsync over SSH :22──►  /var/www/personal_website/
                                                     ▲ read
 browser ──HTTP :80──► ufw (LAN only) ──► nginx ─────┘
         http://<pi-ip>/                   picks the file for the URL path
```

How each piece is decided:

- **Which port.** The browser sees `http://` and fills in port 80 itself. Only
  one program may listen on a port, so Pi-hole's admin UI was moved to 8080
  first ([`pihole/README.md`](../pihole/README.md#34-move-the-admin-ui-off-ports-80443)).
- **Which site.** nginx matches the request's `Host:` header against
  `server_name`. We run one site, so `_` matches anything. Later, several sites
  can share port 80 by differing only in `server_name`.
- **Which file.** `root` plus the URL path. `/` means the directory, so nginx
  looks for `index.html`. No file means 404; a directory without an index (and
  listing off) means 403.
- **Who may read it.** nginx's worker runs as `www-data`, a different user from
  mine, so it is "other" as far as file modes go. The deploy script forces 755 on
  directories and 644 on files so that works whatever modes the laptop has.
- **sites-available / sites-enabled.** The config lives in `sites-available/`;
  a symlink in `sites-enabled/` is what turns it on. Removing the link disables
  the site without deleting the file.

---

## 3. Setup from scratch

Prerequisites: [`base/`](../base/README.md) (SSH by key, firewall), and
[`pihole/`](../pihole/README.md) with its admin UI already moved off 80/443 (if
Pi-hole is installed on the same Pi).

### 3.1 Firewall

```bash
sudo ufw allow from <lan-cidr> to any port 80 proto tcp comment 'Web server (HTTP)'
```

On the original build the 80 and 443 rules were created during the Pi-hole
step, labelled "Pi-hole admin UI"; the rules are right, the labels are stale.
Port 443 stays open to the LAN with nothing listening until TLS is set up.

### 3.2 Install nginx and make the web root (on the Pi)

```bash
sudo apt install -y nginx
sudo mkdir -p /var/www/personal_website
sudo chown "$USER": /var/www/personal_website
```

The web root belongs to my user so deploys need no `sudo`, and stays
world-readable so nginx can serve from it.

### 3.3 Install the server config

From the repo root on the laptop:

```bash
scp personal_website/nginx/personal_website.conf <pi-user>@<pi-ip>:/tmp/
```

On the Pi:

```bash
sudo cp /tmp/personal_website.conf /etc/nginx/sites-available/personal_website
sudo ln -s /etc/nginx/sites-available/personal_website /etc/nginx/sites-enabled/personal_website
sudo rm /etc/nginx/sites-enabled/default    # otherwise its welcome page can win
sudo nginx -t                               # always test before reloading
sudo systemctl reload nginx                 # reload keeps existing connections up
```

### 3.4 Deploy

```bash
cp base/pi.env.example base/pi.env          # once; fill in PI_USER and PI_ADDRESS
personal_website/scripts/deploy.sh --dry-run   # what would change
personal_website/scripts/deploy.sh
```

`--delete` is on: the Pi's copy is made to match `site/`, so a file removed from
the repo disappears from the site.

### Previewing without the Pi

```bash
python3 -m http.server 8000 --directory personal_website/site
# then http://localhost:8000/
```

---

## 4. How to verify

| Check | Command | Expect |
|---|---|---|
| Config valid (Pi) | `sudo nginx -t` | `syntax is ok`, `test is successful` |
| nginx owns port 80 (Pi) | `sudo ss -tlpn \| grep ':80\b'` | `nginx` on `0.0.0.0:80` and `[::]:80` |
| Serves locally (Pi) | `curl -sI http://localhost/ \| head -3` | `200 OK`, `Server: nginx` with **no version number** |
| Reaches it from the LAN | `curl -sI http://<pi-ip>/` (laptop) | same |
| Your content, not the stock page | open `http://<pi-ip>/` in a browser | your `index.html` |
| A second device | open the same URL on a phone on the same Wi-Fi | same page |
| Not served to the world | (later) check from outside the LAN | no answer |

The "your content" row also proves the right server block is live: the default
site serves `/var/www/html`, not our web root.

---

## 5. Failure modes and troubleshooting

| # | Symptom | Cause | How to confirm | Fix |
|---|---|---|---|---|
| 1 | `sudo nginx -t` says `command not found` | The command was run on the **laptop**, not the Pi. Hit on this build. | The prompt: `<user>@<laptop>` vs `<pi-user>@<pi-hostname>` | `ssh <pi-user>@<pi-ip>` first. Checks "on the Pi" mean in that session |
| 2 | The stock "Welcome to nginx!" page appears | The `default` site is still enabled and wins | `ls /etc/nginx/sites-enabled/` | `sudo rm /etc/nginx/sites-enabled/default`, `nginx -t`, reload |
| 3 | `403 Forbidden` | Web root has no `index.html`, or `www-data` cannot read a file or traverse a directory | `ls -la /var/www/personal_website`; `sudo tail /var/log/nginx/error.log` | Deploy again (the script sets 755/644) |
| 4 | `404 Not Found` | Wrong path or filename (Linux is case-sensitive: `Index.html` is not `index.html`) | `ls` the web root; compare to the URL | Fix the name, deploy |
| 5 | nginx will not start or reload: `address already in use` | Another program holds port 80 | `sudo ss -tlpn \| grep ':80\b'` | Move that program, as was done for Pi-hole's UI. **Avoided on this build** by moving Pi-hole first |
| 6 | `deploy.sh`: `Permission denied` writing to the Pi | Web root is not owned by my user | `ls -ld /var/www/personal_website` on the Pi | `sudo chown "$USER": /var/www/personal_website` |
| 7 | `deploy.sh`: `Missing .../base/pi.env` | The git-ignored env file does not exist on this machine | `ls base/pi.env` | Copy from `pi.env.example` and fill in |
| 8 | `<hostname>.local` does not resolve from the laptop | mDNS does not cross WSL2's NAT | `ping <hostname>.local` fails; IP works | Use the IP (`PI_ADDRESS`), or a Pi-hole Local DNS record |
| 9 | The home page scrolls sideways on a phone (556px of content in a 320px viewport). **Hit on this build** | A grid track written as `1fr` cannot shrink below its content's minimum width, so one long unbreakable string (here the placeholder `[[NUMBER]]`) widened the whole page | In the browser at 320px: `document.documentElement.scrollWidth` exceeds the viewport; listing elements whose right edge passes it pointed at `.stat` | `minmax(0, 1fr)` in every grid, and `overflow-wrap` on text. A real email address or URL would have done the same |
| 10 | A 375px headless screenshot looks cropped on the right | Headless Edge/Chrome will not make a window narrower than about 500px, so the shot is a wider layout cut to 375px | Text is cut mid-word while `scrollWidth` reports no overflow | Show the page in a 375px `<iframe>` inside a wider window and screenshot that |

Logs: `/var/log/nginx/access.log` (every request) and `error.log` (why a request
failed). Watching `access.log` while loading the page is the clearest view of
what a browser actually asks for.

### Security notes

- Reachable from the LAN only (firewall); there is no route in from the internet
  yet, so there is nothing to attack from outside.
- `server_tokens off` keeps the exact nginx version out of headers and error pages.
- A static site has no login, no form, no upload: nothing to leak or abuse beyond
  the files themselves. Do not put anything in `site/` that is not meant to be public.

---

## Deferred

Decisions that come before the site is reachable from outside the LAN:

- **Is the connection behind CGNAT?** Compare the router's WAN address (System →
  Device Information) with the public address seen from outside. Probably yes,
  which rules out port forwarding. Not confirmed.
- **How to be reached, if at all:** a tunnel (Cloudflare Tunnel, Tailscale
  Funnel), a reverse tunnel through a small VPS, IPv6 with dynamic DNS, or
  LAN/VPN only. Each trades convenience against who controls the front door.
- **A name:** a LAN-only name through a Pi-hole Local DNS record, then a public
  domain only if the site goes public.
- **TLS:** a local CA (e.g. `mkcert`) to practise on the LAN; a public
  certificate only once there is a public name.

---

## Status

- [x] Pi-hole's admin UI moved to 8080/8443, freeing 80/443
- [x] nginx installed; `nginx -t` passes
- [x] Web root, server config and deploy script in the repo
- [x] Placeholder deployed with `deploy.sh`; loads in a browser on the LAN
- [ ] Confirmed from a second device (phone)
- [ ] `Server:` header shows no version (confirms `server_tokens off` is live)
- [x] Portfolio template built: home, projects, 404, one stylesheet, one script
- [x] Checked in Edge at 320 / 375 / 768 / 1024 / 1440 px: no horizontal scroll, expected grid columns, 44px tap targets, mobile menu, lightbox, deep links clear the sticky header, no console messages
- [ ] Custom 404 page live: reinstall the nginx config (see [`EDITING.md`](EDITING.md#one-time-the-custom-404-page))
- [ ] Real content (`grep -rn '\[\[' site` prints nothing)
- [ ] Lighthouse scores (not run: it needs DevTools or CI)
- [ ] Escape key and a screen reader tried by hand (the harness synthesised events; native `<dialog>` handles Escape)
- [ ] LAN name via Pi-hole Local DNS
- [ ] CGNAT check
- [ ] Decision on public access (tunnel / VPS / VPN / none)
- [ ] TLS
