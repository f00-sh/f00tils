# f00tils — fish (conf.d loads for every fish session)
# Bare names → /usr/lib/f00/bin when replace is enabled.

function __f00_replace_enabled
    set -l cfg "$HOME/.config/f00/config"
    if set -q XDG_CONFIG_HOME
        set cfg "$XDG_CONFIG_HOME/f00/config"
    end
    if not test -f "$cfg"
        return 0
    end
    if grep -Eiq '^[[:space:]]*replace[[:space:]]*=[[:space:]]*(false|no|0|none)([[:space:]]|#|$)' "$cfg" 2>/dev/null
        return 1
    end
    return 0
end

function __f00_path_prepend
    set -l d $argv[1]
    test -n "$d"; or return
    test -d "$d"; or return
    if not contains -- "$d" $PATH
        set -gx PATH "$d" $PATH
    end
end

if __f00_replace_enabled
    if test -n "$HOME"; and test -x "$HOME/.local/bin/f00"
        __f00_path_prepend "$HOME/.local/bin"
    end
    __f00_path_prepend /usr/lib/f00/bin
end

functions -e __f00_replace_enabled __f00_path_prepend
