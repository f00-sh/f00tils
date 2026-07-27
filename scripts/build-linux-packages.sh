#!/usr/bin/env bash
# Build .deb, .rpm, and Arch packages from ASM release tarballs using nfpm.
# Usage: build-linux-packages.sh <version> <assets-dir> <out-dir>
# Example: build-linux-packages.sh 0.15.0 ./dist ./dist
set -euo pipefail

VERSION="${1:?version required (no v prefix)}"
ASSETS="${2:?assets dir required}"
OUT="${3:?out dir required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${ROOT}/packaging/nfpm/f00.yaml"
NFPM="${NFPM:-nfpm}"

if ! command -v "${NFPM}" >/dev/null 2>&1; then
  if [[ -x /tmp/nfpm ]]; then
    NFPM=/tmp/nfpm
  else
    echo "nfpm not found; install from https://nfpm.goreleaser.com/" >&2
    exit 1
  fi
fi

mkdir -p "${OUT}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

# Full multicall link set (keep in sync with install.sh TOOLS_ALL)
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
  base64 basenc base32 dircolors chroot stty stdbuf runcon chcon config grep egrep fgrep find xargs diff cmp diff3 sdiff
)

render_nfpm() {
  local arch="$1" bin_path="$2" man_dir="$3" links_dir="$4" supersede_dir="$5" cfg="$6"
  sed \
    -e "s|\${VERSION}|${VERSION}|g" \
    -e "s|\${ARCH}|${arch}|g" \
    -e "s|\${BIN_PATH}|${bin_path}|g" \
    -e "s|\${MAN_DIR}|${man_dir}|g" \
    -e "s|\${LINKS_DIR}|${links_dir}|g" \
    -e "s|\${SUPERSEDE_DIR}|${supersede_dir}|g" \
    -e "s|\${PATH_SH}|${ROOT}/packaging/shell/path.sh|g" \
    -e "s|\${PROFILE_SH}|${ROOT}/packaging/shell/f00.sh|g" \
    -e "s|\${ZSHENV}|${ROOT}/packaging/shell/zshenv|g" \
    -e "s|\${PROFILE_FISH}|${ROOT}/packaging/shell/f00.fish|g" \
    "${TEMPLATE}" > "${cfg}"
}

stage_links() {
  local links_dir="$1"
  local supersede_dir="$2"
  mkdir -p "${links_dir}" "${supersede_dir}"
  local t
  for t in "${TOOLS_ALL[@]}"; do
    # /usr/bin/f00-* (always; no conflict with coreutils)
    ln -sfn f00 "${links_dir}/f00-${t}"
    # /usr/lib/f00/bin/<bare> → ../../../bin/f00 (PATH supersede; default ON)
    ln -sfn ../../../bin/f00 "${supersede_dir}/${t}"
  done
  # test/[ pair
  ln -sfn f00 "${links_dir}/f00-["
  ln -sfn ../../../bin/f00 "${supersede_dir}/["
}

build_one() {
  local asset_stem="$1"  # e.g. f00-0.15.0-linux-x86_64
  local arch="$2"        # nfpm arch: amd64
  local tarball="${ASSETS}/${asset_stem}.tar.gz"
  if [[ ! -f "${tarball}" ]]; then
    # also accept alias naming without version prefix variants
    echo "skip missing ${tarball}" >&2
    return 0
  fi

  local stage="${WORKDIR}/${asset_stem}"
  mkdir -p "${stage}"
  tar -xzf "${tarball}" -C "${stage}"
  local bin=""
  while IFS= read -r -d '' cand; do
    bin="${cand}"
    break
  done < <(find "${stage}" -type f -name f00 -print0 2>/dev/null)
  if [[ -z "${bin}" || ! -f "${bin}" ]]; then
    echo "binary not found in ${tarball}" >&2
    return 1
  fi
  chmod +x "${bin}"

  local man_dir="${WORKDIR}/man1-${arch}"
  mkdir -p "${man_dir}"
  local man_count=0
  while IFS= read -r -d '' manf; do
    cp "${manf}" "${man_dir}/"
    man_count=$((man_count + 1))
  done < <(find "${stage}" -type f -name 'f00*.1' -print0 2>/dev/null)
  if [[ "${man_count}" -eq 0 && -d "${ROOT}/asm/man/man1" ]]; then
    cp -a "${ROOT}/asm/man/man1/f00"*.1 "${man_dir}/" 2>/dev/null || true
  fi
  if [[ ! -f "${man_dir}/f00.1" ]]; then
    echo "man page f00.1 not found" >&2
    return 1
  fi

  local links_dir="${WORKDIR}/links-${arch}"
  local supersede_dir="${WORKDIR}/supersede-${arch}"
  stage_links "${links_dir}" "${supersede_dir}"

  local cfg="${WORKDIR}/nfpm-${arch}.yaml"
  render_nfpm "${arch}" "${bin}" "${man_dir}" "${links_dir}" "${supersede_dir}" "${cfg}"

  "${NFPM}" package --config "${cfg}" --packager deb --target "${OUT}"
  "${NFPM}" package --config "${cfg}" --packager rpm --target "${OUT}"
  "${NFPM}" package --config "${cfg}" --packager archlinux --target "${OUT}" 2>/dev/null \
    || "${NFPM}" package --config "${cfg}" --packager apk --target "${OUT}" 2>/dev/null \
    || true
  echo "built packages for ${asset_stem} (${arch})"
}

# Preferred ASM asset name from release.yml
build_one "f00-${VERSION}-linux-x86_64" "amd64"
# Installer-friendly alias tarball (same bits)
if [[ ! -f "${ASSETS}/f00-${VERSION}-linux-x86_64.tar.gz" \
   && -f "${ASSETS}/f00-${VERSION}-x86_64-linux.tar.gz" ]]; then
  build_one "f00-${VERSION}-x86_64-linux" "amd64"
fi

echo "linux packages in ${OUT}:"
ls -la "${OUT}"/*.{deb,rpm,pkg.tar.zst,apk} 2>/dev/null || ls -la "${OUT}"
