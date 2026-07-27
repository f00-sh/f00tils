# f00tils — bash/sh login shells (/etc/profile.d)
# Bare names (ls, cat, grep, find, diff, …) → /usr/lib/f00/bin → f00 multicall.
# See /usr/lib/f00/shell/path.sh
#
# zsh interactive terminals do NOT load profile.d — /etc/zsh/zshenv covers them.

if [ -r /usr/lib/f00/shell/path.sh ]; then
  # shellcheck source=/dev/null
  . /usr/lib/f00/shell/path.sh
elif [ -r /usr/share/f00/path.sh ]; then
  # shellcheck source=/dev/null
  . /usr/share/f00/path.sh
fi
