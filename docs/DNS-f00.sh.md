# DNS / f00.sh ecosystem

Ops note. Not product surface.

## Domains (Porkbun)

| Host | Role | Target |
|------|------|--------|
| `f00.sh` | Brand landing (hub) | GitHub Pages (A/AAAA → GitHub) |
| `www.f00.sh` | Apex alias | CNAME → `f00-sh.github.io` (or `f00-sh.github.io` after org transfer) |
| `coreutils.f00.sh` | **f00tils** product site + installer | CNAME → GitHub Pages owner |
| `clun.f00.sh` | **clun** product (dual with `clun.sh`) | CNAME / URL → clun Pages |

Apex `f00.sh` keeps GitHub Pages A/AAAA records. Product sites are subdomains.

Mail (Proton) TXT/MX/DKIM on apex is unchanged.

## Product mapping

| Product | Repo (target org) | Site | Install |
|---------|-------------------|------|---------|
| Landing | `f00-sh/f00` (planned) | https://f00.sh | n/a |
| f00tils | `f00-sh/f00tils` (temp: `f00-sh/f00tils`) | https://coreutils.f00.sh | `curl -fsSL https://coreutils.f00.sh/install.sh \| bash` |
| clun | `f00-sh/clun` (temp: `f00-sh/clun`) | https://clun.sh · https://clun.f00.sh | `curl -fsSL https://clun.sh/install \| sh` |

## GitHub Pages

Each product repo ships `site/CNAME` with its primary host. After org transfer, update DNS CNAME targets from `f00-sh.github.io` → `f00-sh.github.io`.
