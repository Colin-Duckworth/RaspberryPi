# Editing the portfolio site

How to fill in, extend and publish the site in [`site/`](site/). The server side
(nginx, the Pi, the firewall) is in [`README.md`](README.md); this file is only
about the content.

Everything in `site/` is plain HTML, one stylesheet and one small script. There is
no build step and no dependency to install.

```
site/
├── index.html          home page
├── projects.html       all projects (flagship write-ups + smaller cards)
├── 404.html            shown for any missing URL (needs the nginx error_page, see below)
├── css/styles.css      all styling; colours, type and spacing are tokens at the top
├── js/main.js          footer year, mobile menu, image lightbox
├── assets/             favicon.svg, the resume PDF
└── images/             og-image.png, placeholders, and one folder per project
```

Only `site/` is published. This file, the nginx config and the scripts stay in
the repo and never reach the web server.

---

## 1. Preview locally

```bash
python3 -m http.server 8000 --directory personal_website/site
```

Open `http://localhost:8000/`. Opening `site/index.html` straight from disk also
works, except `404.html` (its asset paths start with `/` on purpose, because
nginx serves it for any depth of missing URL).

## 2. Replace the placeholders

Every unfilled value is visibly marked `[[LIKE THIS]]`. List them all:

```bash
grep -rn '\[\[' personal_website/site --include='*.html' --include='*.svg'
```

You are done when that prints nothing. The ones that are not obvious:

| Placeholder | Where | Notes |
|---|---|---|
| `[[DOMAIN]]` | `<link rel="canonical">`, `og:` and `twitter:` tags, JSON-LD, both pages | Needed for correct link previews. Leave until there is a public name |
| `[[SHORT NAME]]` | nav wordmark, on all three pages | e.g. `Jane D.` |
| `[[LINKEDIN URL]]` etc. | contact section and footer | **Delete the whole `<a>`** (and its `<li>` in the footer) for any you do not have; an empty link is worse than none |
| `FL` in `assets/favicon.svg` | the monogram | Your initials |
| `[[IMAGE 16:10]]` | `images/placeholder-16x10.svg` | Replace the `src` (and `href` in galleries) with real images |
| `[[PROFILE PHOTO]]` | `images/placeholder-4x5.svg` | Point the hero `<img>` at `images/profile.jpg` |

### Images

- Resize to **1600px on the long edge at most**, and compress. Keep real
  `width` and `height` attributes on every `<img>` so the page does not jump as
  images load.
- WebP with a JPG fallback is the smallest option:

  ```html
  <picture>
    <source srcset="images/projects/slug/fig-1.webp" type="image/webp">
    <img src="images/projects/slug/fig-1.jpg" width="1600" height="1000" loading="lazy" alt="...">
  </picture>
  ```

- Every image needs `alt` text that says what it shows. Decorative images use `alt=""`.
- `images/og-image.png` is a plain grey placeholder. Replace it with a 1200x630
  image (keep the name, or update the two `og:image`/`twitter:image` tags on
  each page if you switch to `.jpg`).

## 3. Add a project

Each section of `projects.html` starts with a commented **template**. Copy it,
fill it in, and paste it below the last one.

**Tier 1 (flagship, full write-up):** copy the `<article>` from the template
comment above `class="flagship"`.

1. Pick a slug: lowercase, hyphens, unique (`lake-mapping`). It is used in three
   places that must match: the article `id`, its `aria-labelledby` (`<slug>-title`),
   and the home-page card's link (`projects.html#<slug>`).
2. Put images in `images/projects/<slug>/`.
3. Delete any button in `.project-links` you have no link for. The links open in
   a new tab.
4. Gallery images are wrapped in `<a class="gallery-link" href="<full-size file>" data-lightbox>`;
   keep the `data-lightbox` attribute and the lightbox works with no further code.

**Tier 2 (smaller project card):** copy one `<li>` from the template comment
above the "Smaller Projects" section into a group's list. For a new category,
copy a whole `<div class="group">`. These cards have no images.

## 4. Feature a project on the home page

The home page shows exactly three cards (a 3-column grid on desktop). In
`index.html`, edit or replace a card using the template comment above
"Featured Projects": set the `href` to `projects.html#<slug>` of a Tier 1
article, plus a cover image, a category, a title and a one-line summary.

## 5. Swap the resume PDF

Replace `site/assets/firstname-lastname-resume.pdf` with your file **under the
same name**, and deploy. To use a different name, update the one link in the hero
section of `index.html`.

## 6. Publish

This site is served by nginx on the Pi, not GitHub Pages, so there is no `CNAME`
file. From the repo root:

```bash
personal_website/scripts/deploy.sh --dry-run    # what would change
personal_website/scripts/deploy.sh
```

Reload the page (Ctrl+Shift+R to bypass the browser cache).

### One-time: the custom 404 page

`404.html` only shows if nginx is told to use it. That lives in
`nginx/personal_website.conf` (the `error_page 404 /404.html;` block), so after
pulling that change, install the config again on the Pi:

```bash
scp personal_website/nginx/personal_website.conf <pi-user>@<pi-ip>:/tmp/
# then, on the Pi:
sudo cp /tmp/personal_website.conf /etc/nginx/sites-available/personal_website
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null -w '%{http_code}\n' http://<pi-ip>/no-such-page    # 404, with the site's own page
curl -s http://<pi-ip>/no-such-page | grep -o 'Page not found'
```

### Moving to GitHub Pages instead

If the site ever goes there: publish the contents of `site/` as the site root,
and add a `CNAME` file containing the domain. Nothing else changes, since all
paths are relative.

---

## Notes on how it is built

- **Fonts.** One family (Inter) from Google Fonts with `font-display: swap`,
  after a system-font stack, so text shows immediately and the site still looks
  right if the font is blocked. The cost: every visitor's browser contacts Google
  to fetch it. To avoid that, download the font files into `site/assets/fonts/`,
  add `@font-face` rules to `styles.css`, and delete the three `fonts.*` link
  tags from each page.
- **Light mode only**, by design. No dark-mode media query exists.
- **No JavaScript is required to read the site.** With JS off, the nav links stay
  visible and gallery images link straight to the full-size file. `main.js` only
  adds the mobile menu, the lightbox, the header background and the footer year.
- **Lightbox** uses the browser's native `<dialog>`: it provides the backdrop,
  Escape-to-close, an inert page behind it and contained Tab focus. `main.js`
  adds the image, the caption, closing on backdrop click, and returning focus to
  the image you clicked.
- **Grids use `minmax(0, 1fr)`, not `1fr`.** A bare `1fr` track cannot shrink
  below its content's minimum width, so one long unbreakable string (an email
  address, a URL, `[[NUMBER]]`) widens the whole page on a phone.
- **Breakpoints:** mobile-first; extra rules at 768px and 1024px.
