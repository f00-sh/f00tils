# DNS / f00.sh ecosystem

Ops note. Not product surface.

## Authority

- **Registrar:** Porkbun (domain registration only)
- **DNS + edge:** Cloudflare zone `f00.sh`
- **NS:** `brett.ns.cloudflare.com`, `gracie.ns.cloudflare.com`

## Host map

| Host | Role | Target |
|------|------|--------|
| `f00.sh` | Brand landing (hub) | CNAME → `f00-be0.pages.dev` (proxied) |
| `www.f00.sh` | Apex alias | CNAME → `f00-be0.pages.dev` (proxied) |
| `coreutils.f00.sh` | **f00tils** product site + installer | CNAME → `f00-coreutils.pages.dev` (proxied) |
| `clun.f00.sh` | **clun** product site + installer | CNAME → `f00-clun.pages.dev` (proxied) |
| `cel.f00.sh` | **Cel Index** web app | CNAME → `f00-cel.pages.dev` (proxied) |
| `dist.f00.sh` | Package current channel (R2) | R2 custom domain → bucket `f00-releases` (proxied) |

Mail (Proton) TXT/MX/DKIM/DMARC on apex is DNS-only.

## Product mapping

| Product | Repo | Site | Packages | Install |
|---------|------|------|----------|---------|
| Landing | `f00-sh/f00` | https://f00.sh | n/a | n/a |
| f00tils | `f00-sh/f00tils` | https://coreutils.f00.sh | https://dist.f00.sh/f00tils/current/ | `curl -fsSL https://coreutils.f00.sh/install.sh \| bash` |
| clun | `f00-sh/clun` | https://clun.f00.sh | https://dist.f00.sh/clun/current/ | `curl -fsSL https://clun.f00.sh/install \| sh` |
| Cel Index | `f00-sh/cel` | https://cel.f00.sh | n/a | web app |

## R2

- Bucket: `f00-releases`
- Public custom domain: `dist.f00.sh` (SSL active)
- Layout: `{product}/current/*` plus versioned `{product}/{ver}/*` on release
- Release workflows upload on publish; installers prefer R2, then product edge metadata, then GitHub Releases

## Cloudflare Pages

| Project | Domain(s) | Source tree | Deploy |
|---------|-----------|-------------|--------|
| `f00` | f00.sh, www.f00.sh | `site/` | `.github/workflows/pages.yml` → wrangler |
| `f00-coreutils` | coreutils.f00.sh | `site/` | same |
| `f00-clun` | clun.f00.sh | `site/` | same |
| `f00-cel` | cel.f00.sh | `site/` + `functions/` | same |

GitHub Pages is **off**. Do not re-enable. Native Pages↔GitHub source connect is optional; Actions + wrangler is the supported path.
