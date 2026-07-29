# Homebrew formula for f00 (pure assembly multicall coreutils suite).
#
# Install:
#   brew install theesfeld/tap/f00
#
# Official installer:
#   curl -fsSL https://coreutils.f00.sh/install.sh | bash

class F00 < Formula
  desc "f00tils — pure assembly coreutils replacement (multicall, freestanding)"
  homepage "https://coreutils.f00.sh"
  version "0.16.10"
  license "MIT"

  on_linux do
    on_intel do
      url "https://github.com/theesfeld/f00tils/releases/download/v#{version}/f00-0.16.10-linux-x86_64.tar.gz"
      sha256 "c34866ac7dd1de7e79e661fb9dc038ef31dbbbaec210ccea8e15e6263109b8b9"
    end
  end

  def install
    bin.install "f00"
    utils = %w[
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
    ]
    utils.each do |u|
      bin.install_symlink "f00" => "f00-#{u}"
      # bare names in libexec; default PATH via caveats / shellenv
      libexec.install_symlink bin/"f00" => u
    end
    libexec.install_symlink bin/"f00" => "["
    man1.install Dir["man/man1/*.1"] if Dir.exist?("man/man1")
    (prefix/"etc/profile.d").mkpath
    (prefix/"etc/profile.d/f00.sh").write <<~EOS
      # f00tils brew: prepend libexec bare names when replace enabled
      _f00_libbin="#{libexec}"
      _f00_replace_enabled() {
        local cfg="${XDG_CONFIG_HOME:-${HOME}/.config}/f00/config"
        [ -f "$cfg" ] || return 0
        if grep -Eiq '^[[:space:]]*replace[[:space:]]*=[[:space:]]*(false|no|0|none)([[:space:]]|#|$)' "$cfg" 2>/dev/null; then
          return 1
        fi
        return 0
      }
      if [ -d "$_f00_libbin" ] && _f00_replace_enabled; then
        case ":${PATH}:" in
          *":${_f00_libbin}:"*) ;;
          *) PATH="${_f00_libbin}${PATH:+:}${PATH}"; export PATH ;;
        esac
      fi
      unset _f00_libbin
      unset -f _f00_replace_enabled 2>/dev/null || true
    EOS
  end

  def caveats
    <<~EOS
      f00tils replaces coreutils by default via bare names in:
        #{libexec}
      Add to your shell rc (or source the profile snippet):
        export PATH="#{libexec}:$PATH"
      Or:  echo 'export PATH="#{libexec}:$PATH"' >> ~/.zshrc
      Opt out:  f00-config replace off   # writes replace = false
    EOS
  end

  test do
    assert_match "f00", shell_output("#{bin}/f00-ls --version")
    system bin/"f00-true"
  end
end
