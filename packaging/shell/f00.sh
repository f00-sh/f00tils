# f00tils — default GNU userland replacement via PATH
# Bare names (ls, cat, grep, find, diff, …) live in supersede dirs → f00 multicall.
# They never overwrite /usr/bin/* package files (no file conflicts).
#
# Covers coreutils + grep + findutils + diffutils (full TOOLS_ALL).
#
# Default: ON. Toggle in XDG config:
#   replace = false
# or: f00-config replace off | on
#
# Search order (first wins):
#   1. ~/.local/bin   — curl / make install (full tool set when present)
#   2. /usr/lib/f00/bin — distro package bare names
#
# Requires a new shell (or: source /etc/profile.d/f00.sh).
# zsh interactive: source from ~/.zshrc if login profile is not used.

_f00_replace_enabled() {
  # default ON when config missing / no explicit false
  local cfg="${XDG_CONFIG_HOME:-${HOME}/.config}/f00/config"
  [ -n "${HOME:-}" ] || return 0
  [ -f "$cfg" ] || return 0
  if grep -Eiq '^[[:space:]]*replace[[:space:]]*=[[:space:]]*(false|no|0|none)([[:space:]]|#|$)' "$cfg" 2>/dev/null; then
    return 1
  fi
  return 0
}

_f00_path_prepend() {
  local d="$1"
  [ -n "$d" ] && [ -d "$d" ] || return 0
  case ":${PATH:-}:" in
    *":${d}:"*) ;;
    *) PATH="${d}${PATH:+:}${PATH:-}"; export PATH ;;
  esac
}

if _f00_replace_enabled; then
  # User install first (make install / curl → full 115 bare names)
  if [ -n "${HOME:-}" ] && [ -x "${HOME}/.local/bin/f00" ]; then
    _f00_path_prepend "${HOME}/.local/bin"
  fi
  # Distro package supersede dir (may lag releases — user install wins)
  _f00_path_prepend "/usr/lib/f00/bin"
fi

unset -f _f00_replace_enabled _f00_path_prepend 2>/dev/null || true
