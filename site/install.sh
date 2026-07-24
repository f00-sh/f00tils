#!/usr/bin/env bash
# f00tils installer (binary: f00) — https://f00.sh
#   curl -fsSL https://f00.sh/install.sh | bash
#
# f00tils: pure-assembly multicall coreutils replacement (Linux x86-64 only).
# Default: REPLACE coreutils — multicall `f00` + f00-* + bare names (ls, cat, …)
# in INSTALL_DIR (must win on PATH). Opt out: F00_SUPERSEDE=0 or config replace=false.
#
# Beta pin example:
#   curl -fsSL https://f00.sh/install.sh | F00_VERSION=v0.15.18 bash
#
# Env:
#   INSTALL_DIR      default ~/.local/bin
#   F00_VERSION      release tag (default: latest; default: latest / v0.15.18)
#   F00_REPO         GitHub owner/repo (default: theesfeld/f00)
#   F00_LOCAL        path to a local build directory containing ./f00
#                    (e.g. /path/to/f00/asm) — skips download
#   F00_TOOLS        comma list or "all" (default: all shipped tools)
#   F00_SUPERSEDE    default 1: bare names in INSTALL_DIR; 0 = f00-* only
#   F00_ALIAS        1 = also append shell aliases (usually unnecessary with SUPERSEDE)
#   ADD_PATH         1 = ensure INSTALL_DIR on PATH (default: 1 when missing)
#   F00_NO_COLOR     1 = plain logs
#   F00_MAN          1 = install man pages if present (default: 1)
#
set -euo pipefail

REPO="${F00_REPO:-theesfeld/f00}"
BINARY_NAME="f00"

# Full multicall surface (must stay in sync with asm/Makefile UTILS)
TOOLS_ALL=(
  ls cat true false yes nproc tty whoami basename dirname
  head tail wc tee seq echo pwd sleep
  env printenv realpath readlink pathchk mktemp link unlink sync truncate
  mkdir rmdir chmod touch logname hostid
  cut tr sort uniq rev tac nl fold expand unexpand paste join comm fmt od
  split csplit shuf tsort pr ptx factor numfmt expr
  cp mv rm ln chown chgrp stat df du install mkfifo mknod shred dd dir vdir
  id groups uname arch date users who pinky uptime hostname
  nice nohup timeout kill test printf
  md5sum sha1sum sha256sum sha224sum sha384sum sha512sum b2sum cksum sum
  base64 basenc base32 dircolors chroot stty stdbuf runcon chcon config
)

if [[ -z "${F00_NO_COLOR:-}" && -t 2 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; OK=$'\033[32m'; ERR=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=; DIM=; OK=; ERR=; RESET=
fi

log()  { printf '%s\n' "$*" >&2; }
ok()   { printf "${OK}ok${RESET}  %s\n" "$*" >&2; }
die()  { printf "${ERR}error${RESET}  %s\n" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "need $1"; }

resolve_tag() {
  if [[ -n "${F00_VERSION:-}" ]]; then
    echo "${F00_VERSION}"
    return
  fi
  need curl
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$tag" ]] || die "could not resolve latest release; set F00_VERSION=vX.Y.Z or F00_LOCAL="
  echo "$tag"
}

pick_dir() {
  if [[ -n "${INSTALL_DIR:-}" ]]; then
    echo "$INSTALL_DIR"
    return
  fi
  echo "${HOME}/.local/bin"
}

ensure_path() {
  local dir="$1"
  case ":$PATH:" in
    *":${dir}:"*) return 0 ;;
  esac
  [[ "${ADD_PATH:-1}" == "1" ]] || return 0
  # Only auto-edit shell rc for installs under $HOME (avoid /tmp pollution).
  case "$dir" in
    "$HOME"/*) ;;
    *)
      log "${DIM}add to PATH: export PATH=\"${dir}:\$PATH\"${RESET}"
      return 0
      ;;
  esac
  local rc marker="# f00 installer: PATH (${dir})"
  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    [[ -f "$rc" ]] || continue
    if grep -Fq "$marker" "$rc" 2>/dev/null; then
      ok "PATH already configured in $rc"
      return 0
    fi
    {
      echo ""
      echo "$marker"
      echo "export PATH=\"${dir}:\$PATH\""
    } >>"$rc"
    ok "added ${dir} to PATH in $rc"
    return 0
  done
  log "${DIM}add to PATH: export PATH=\"${dir}:\$PATH\"${RESET}"
}

normalize_tool() {
  # strip optional f00- prefix → short name
  local t="$1"
  t="${t// /}"
  t="${t#f00-}"
  echo "$t"
}

tool_known() {
  local want="$1" u
  for u in "${TOOLS_ALL[@]}"; do
    [[ "$u" == "$want" ]] && return 0
  done
  return 1
}

select_tools() {
  local tools="${F00_TOOLS:-all}"
  local -a out=()
  local t n
  if [[ "$tools" == "all" ]]; then
    out=("${TOOLS_ALL[@]}")
  else
    IFS=',' read -ra raw <<<"$tools"
    for t in "${raw[@]}"; do
      n="$(normalize_tool "$t")"
      [[ -n "$n" ]] || continue
      if tool_known "$n"; then
        out+=("$n")
      else
        log "${DIM}skip unknown tool: $t${RESET}"
      fi
    done
  fi
  printf '%s\n' "${out[@]}"
}

install_links() {
  local dir="$1"
  shift
  local t
  for t in "$@"; do
    ln -sfn f00 "${dir}/f00-${t}"
    # Default ON: bare coreutils names (ls, cat, …) next to f00 / f00-*
    if [[ "${F00_SUPERSEDE:-1}" == "1" ]]; then
      if [[ "$t" == "test" ]]; then
        ln -sfn f00 "${dir}/["
      fi
      ln -sfn f00 "${dir}/${t}"
    fi
  done
  if [[ "${F00_SUPERSEDE:-1}" == "1" ]]; then
    ok "links: f00-* × $# + bare names → f00 (replace default; F00_SUPERSEDE=0 to skip)"
  else
    ok "links: f00-* × $# → f00 (side-by-side; bare names off)"
  fi
}

maybe_alias() {
  [[ "${F00_ALIAS:-0}" == "1" ]] || return 0
  local dir="$1"
  shift
  local rc="${HOME}/.bashrc"
  [[ -n "${ZSH_VERSION:-}" || "${SHELL:-}" == *zsh* ]] && rc="${HOME}/.zshrc"
  [[ -f "$rc" ]] || touch "$rc"
  local marker="# f00 aliases (installer)"
  if grep -Fq "$marker" "$rc" 2>/dev/null; then
    ok "aliases already present in $rc"
    return 0
  fi
  {
    echo ""
    echo "$marker"
    local t
    for t in "$@"; do
      # only alias common interactive names
      case "$t" in
        ls|cat|head|tail|wc|sort|cp|rm|mv|mkdir|rmdir|echo|env|date|id|pwd|sha256sum|md5sum)
          printf "alias %s='f00-%s'\n" "$t" "$t"
          ;;
      esac
    done
  } >>"$rc"
  ok "aliases appended in $rc"
}

install_man_from() {
  local src_root="$1"
  [[ "${F00_MAN:-1}" == "1" ]] || return 0
  local mandir="${XDG_DATA_HOME:-$HOME/.local/share}/man/man1"
  local n=0
  local f base
  # prefer release layout man/man1/*.1 or man/*.1
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    mkdir -p "$mandir"
    base="$(basename "$f")"
    install -m 644 "$f" "${mandir}/${base}"
    n=$((n + 1))
  done < <(find "$src_root" -type f \( -path '*/man/man1/f00*.1' -o -path '*/man1/f00*.1' \) 2>/dev/null | head -200)
  if [[ "$n" -gt 0 ]]; then
    ok "man pages × ${n} → ${mandir}"
  fi
}

fetch_release() {
  local tmp="$1" tag os arch asset url
  tag="$(resolve_tag)"
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) die "unsupported arch: $arch" ;;
  esac
  case "$os" in
    linux) ;;
    *)
      die "unsupported OS: $os (product is Linux x86-64 freestanding ASM; use F00_LOCAL for a local build)"
      ;;
  esac
  case "$arch" in
    x86_64) ;;
    *)
      die "unsupported arch: $arch (release assets are linux-x86_64; use F00_LOCAL for a local build)"
      ;;
  esac

  # Preferred asset names for ASM multicall releases
  asset="f00-${tag#v}-linux-x86_64.tar.gz"
  url="https://github.com/${REPO}/releases/download/${tag}/${asset}"

  log "fetch ${url}"
  if ! curl -fsSL "$url" -o "${tmp}/f00.tgz"; then
    asset="f00-${tag#v}-x86_64-linux.tar.gz"
    url="https://github.com/${REPO}/releases/download/${tag}/${asset}"
    log "retry ${url}"
    if ! curl -fsSL "$url" -o "${tmp}/f00.tgz"; then
      die "download failed (set F00_VERSION=vX.Y.Z or F00_LOCAL=path/to/asm)"
    fi
  fi
  tar -xzf "${tmp}/f00.tgz" -C "$tmp"
  echo "$tmp"
}

main() {
  printf "\n${BOLD}f00tils${RESET} ${DIM}installer · binary f00 · 0.15.18 multicall${RESET}\n" >&2

  local dir bin
  local tmp=""
  dir="$(pick_dir)"
  mkdir -p "$dir"

  if [[ -n "${F00_LOCAL:-}" ]]; then
    local local_bin="${F00_LOCAL%/}"
    if [[ -f "${local_bin}/f00" ]]; then
      bin="${local_bin}/f00"
    elif [[ -f "${local_bin}" && "$(basename "${local_bin}")" == "f00" ]]; then
      bin="${local_bin}"
      local_bin="$(dirname "$bin")"
    else
      die "F00_LOCAL=${F00_LOCAL} does not contain f00 (build with: cd asm && make)"
    fi
    [[ -x "$bin" ]] || die "not executable: $bin"
    install -m 755 "$bin" "${dir}/f00"
    ok "installed f00 → ${dir}/f00 (from local ${bin})"
    install_man_from "${local_bin}"
    # also try repo man tree if local is asm/
    install_man_from "${local_bin}/man" 2>/dev/null || true
  else
    need curl
    need tar
    need install
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap '[[ -n "${tmp:-}" ]] && rm -rf -- "$tmp"' EXIT
    fetch_release "$tmp" >/dev/null
    bin="$(find "$tmp" -type f -name f00 | head -1)"
    [[ -n "$bin" && -f "$bin" ]] || die "archive missing f00 binary"
    install -m 755 "$bin" "${dir}/f00"
    ok "installed f00 → ${dir}/f00"
    install_man_from "$tmp"
  fi

  mapfile -t SELECTED < <(select_tools)
  [[ "${#SELECTED[@]}" -gt 0 ]] || die "no tools selected (F00_TOOLS=${F00_TOOLS:-all})"
  install_links "$dir" "${SELECTED[@]}"
  maybe_alias "$dir" "${SELECTED[@]}"
  seed_xdg_config "$dir"

  ensure_path "$dir"
  printf "\n${BOLD}done${RESET}. try: ${BOLD}cat --version${RESET} · ${BOLD}ls --help${RESET} · ${BOLD}f00-config replace status${RESET}\n" >&2
  printf "${DIM}default: bare names replace coreutils when INSTALL_DIR wins on PATH${RESET}\n" >&2
  printf "${DIM}opt-out: F00_SUPERSEDE=0  or  f00-config replace off  (replace = false)${RESET}\n" >&2
  printf "${DIM}knobs: F00_TOOLS=all|ls,cat,…  F00_SUPERSEDE=0  F00_LOCAL=asm  F00_VERSION=v0.15.18${RESET}\n" >&2
  printf "${DIM}config: ~/.config/f00  ·  themes: f00-config theme list|set|pick${RESET}\n" >&2
}

# Seed XDG config + theme files once (never clobber existing config).
# Always under $XDG_CONFIG_HOME/f00 or ~/.config/f00 — never random paths under $HOME alone.
seed_xdg_config() {
  local bindir="${1:-${INSTALL_DIR:-$HOME/.local/bin}}"
  local cfg_root="${XDG_CONFIG_HOME:-$HOME/.config}/f00"
  local themes_dir="${cfg_root}/themes"
  mkdir -p "${themes_dir}"
  if [[ ! -f "${cfg_root}/config" ]]; then
    cat >"${cfg_root}/config" <<'EOF'
# f00tils — https://f00.sh  (docs/CONFIG.md)
# replace = true  → bare names (ls/cat/…) via installer PATH or /usr/lib/f00/bin
# replace = false → f00-* only (side-by-side with GNU coreutils)
replace = true
# Uses your terminal palette by default (theme = terminal).
# theme = auto          # catppuccin mocha/latte from COLORFGBG
# theme = dracula       # f00-config theme list | set | pick
theme = terminal
core = false
color = auto
icons = auto
animations = true
spinner = true

[ls]
git = true
EOF
    ok "seeded ${cfg_root}/config"
  else
    ok "kept existing ${cfg_root}/config"
  fi
  # Prefer local checkout themes; else `f00-config init` seeds builtins into XDG
  local src=""
  if [[ -n "${F00_LOCAL:-}" ]]; then
    local base="${F00_LOCAL%/}"
    [[ -d "${base}/../docs/examples/themes" ]] && src="${base}/../docs/examples/themes"
    [[ -d "${base}/docs/examples/themes" ]] && src="${base}/docs/examples/themes"
  fi
  if [[ -n "$src" && -d "$src" ]]; then
    local n=0
    local f
    for f in "$src"/*.theme; do
      [[ -f "$f" ]] || continue
      local bn
      bn="$(basename "$f")"
      if [[ ! -f "${themes_dir}/${bn}" ]]; then
        install -m 644 "$f" "${themes_dir}/${bn}"
        n=$((n + 1))
      fi
    done
    [[ "$n" -gt 0 ]] && ok "seeded ${n} theme files → ${themes_dir}"
  elif [[ -x "${bindir}/f00" ]]; then
    "${bindir}/f00" config init >/dev/null 2>&1 || true
  fi
}

main "$@"
