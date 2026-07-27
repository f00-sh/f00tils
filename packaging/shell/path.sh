# f00tils — bare-name PATH replace (sourced; not executed)
# Prepends supersede dirs so ls/find/grep/diff resolve to f00, not GNU.
# Never overwrites /usr/bin/* (no pacman file conflicts with coreutils/findutils/…).
#
# Toggle off:  replace = false  in ~/.config/f00/config
#           or f00-config replace off
# GNU clone bytes: export F00_CORE=1  or  --core  (separate from PATH replace)

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
  # User install first (curl / make install → full bare names in ~/.local/bin)
  if [ -n "${HOME:-}" ] && [ -x "${HOME}/.local/bin/f00" ]; then
    _f00_path_prepend "${HOME}/.local/bin"
  fi
  # Distro package supersede dir
  _f00_path_prepend "/usr/lib/f00/bin"
fi

unset -f _f00_replace_enabled _f00_path_prepend 2>/dev/null || true
