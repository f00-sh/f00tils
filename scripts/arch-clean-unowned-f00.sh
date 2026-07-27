#!/usr/bin/env bash
# Remove unowned f00 paths under /usr so pacman/paru can claim them.
#
# Symptom (upgrade fails):
#   error: failed to commit transaction (conflicting files)
#   f00: /usr/bin/f00-grep exists in filesystem
#   f00: /usr/lib/f00/bin/grep exists in filesystem
#   …
#
# Cause: older AUR packages shipped coreutils-only links; userland links
# (grep/find/diffutils) or a root install.sh into /usr left orphans.
# Pacman will not overwrite unowned files without --overwrite.
#
# Usage:
#   sudo ./scripts/arch-clean-unowned-f00.sh
#   paru -Syu f00
# Or one-shot:  paru -S f00 -- --overwrite '/*'
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run as root (sudo $0)" >&2
  exit 1
fi
if ! command -v pacman >/dev/null 2>&1; then
  echo "pacman not found" >&2
  exit 1
fi

removed=0
skipped=0

consider() {
  local f="$1"
  if [[ ! -e "$f" && ! -L "$f" ]]; then
    return 0
  fi
  if pacman -Qo -- "$f" &>/dev/null; then
    echo "keep owned: $f  ($(pacman -Qo -- "$f" 2>/dev/null | tr -d '\n'))"
    skipped=$((skipped + 1))
    return 0
  fi
  echo "remove unowned: $f"
  rm -f -- "$f"
  removed=$((removed + 1))
}

# Prefixed multicall names + bare supersede dir (full 115 surface + test/[)
while IFS= read -r -d '' f; do
  consider "$f"
done < <(find /usr/bin -maxdepth 1 \( -name 'f00' -o -name 'f00-*' \) -print0 2>/dev/null)

if [[ -d /usr/lib/f00 ]]; then
  while IFS= read -r -d '' f; do
    [[ -d "$f" ]] && continue
    consider "$f"
  done < <(find /usr/lib/f00 -print0 2>/dev/null)
fi

for f in /etc/profile.d/f00.sh /etc/fish/conf.d/f00.fish; do
  consider "$f"
done

echo "done: removed=${removed} kept_owned=${skipped}"
echo "next: pacman -Syu f00   # or: paru -Syu f00"
