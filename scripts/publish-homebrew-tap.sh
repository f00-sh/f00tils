#!/usr/bin/env bash
# Push Formula/f00.rb to theesfeld/homebrew-tap.
# Requires: HOMEBREW_TAP_TOKEN (or GH_TOKEN) with contents:write on theesfeld/homebrew-tap
# Usage: publish-homebrew-tap.sh [formula-path]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORMULA="${1:-${ROOT}/Formula/f00.rb}"
TOKEN="${HOMEBREW_TAP_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
REPO="${HOMEBREW_TAP_REPO:-theesfeld/homebrew-tap}"
BRANCH="${HOMEBREW_TAP_BRANCH:-main}"

if [[ -z "${TOKEN}" ]]; then
  echo "skip homebrew: no HOMEBREW_TAP_TOKEN / GH_TOKEN" >&2
  exit 0
fi
if [[ ! -f "${FORMULA}" ]]; then
  echo "missing formula ${FORMULA}" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

git clone --depth 1 "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "${WORKDIR}/tap"
mkdir -p "${WORKDIR}/tap/Formula"
cp "${FORMULA}" "${WORKDIR}/tap/Formula/f00.rb"

# First commit needs a default branch; empty repos have none until first push.
cd "${WORKDIR}/tap"
git config user.name "f00-release-bot"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if [[ -z "$(git rev-parse --verify HEAD 2>/dev/null || true)" ]]; then
  git checkout -B "${BRANCH}"
  printf '# Homebrew tap for theesfeld projects\n\n```bash\nbrew install f00-sh/tap/f00\n```\n' > README.md
  git add README.md Formula/f00.rb
  git commit -m "feat: add f00 formula"
  git push -u origin "${BRANCH}"
else
  git checkout "${BRANCH}" 2>/dev/null || git checkout -B "${BRANCH}"
  git add Formula/f00.rb
  if git diff --cached --quiet; then
    echo "homebrew: formula unchanged"
    exit 0
  fi
  VER="$(grep -E '^\s*version "' Formula/f00.rb | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
  git commit -m "chore(f00): bump formula to v${VER}"
  git push origin "HEAD:${BRANCH}"
fi

echo "published homebrew formula to ${REPO}"
