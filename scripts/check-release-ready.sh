#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)}"
TAG="v${VERSION}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
NOTES="docs/release-notes-v${VERSION}.md"
BRANCH="$(git branch --show-current)"
RELEASE_REMOTE="${RELEASE_REMOTE:-$(git config --get "branch.${BRANCH}.remote" || true)}"
RELEASE_REMOTE="${RELEASE_REMOTE:-origin}"
REMOTE_URL="$(git remote get-url "$RELEASE_REMOTE")"
RELEASE_REPO="${RELEASE_REPO:-$(printf '%s' "$REMOTE_URL" | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')}"

[[ "$VERSION" == "$PLIST_VERSION" ]] || { echo "Info.plist version mismatch" >&2; exit 1; }
[[ -f "$NOTES" ]] || { echo "Missing release notes: $NOTES" >&2; exit 1; }
grep -q "## ${VERSION} -" CHANGELOG.md || { echo "CHANGELOG is missing $VERSION" >&2; exit 1; }
grep -q "codexU-${VERSION}-mac-arm64.dmg" README.md || { echo "README.md artifact examples are stale" >&2; exit 1; }
grep -q "codexU-${VERSION}-mac-arm64.dmg" README.en.md || { echo "README.en.md artifact examples are stale" >&2; exit 1; }

for readme in README.md README.en.md; do
  while IFS= read -r image; do
    [[ -f "$image" ]] || { echo "$readme references missing image: $image" >&2; exit 1; }
  done < <(sed -nE 's#.*\]\((docs/[^)]+\.(png|jpg|jpeg|webp))\).*#\1#p' "$readme")
  grep -q "docs/screenshot-v${VERSION}-" "$readme" || { echo "$readme is missing current-version screenshots" >&2; exit 1; }
done

if rg -n '关注公众号|扫码关注|用户交流群|交流群二维码|微信群|公众号二维码' README.md README.en.md docs --glob '*.md'; then
  echo "Promotional QR or community-channel copy remains in published docs" >&2
  exit 1
fi

if rg -n 'screenshot-v(0\.|1\.0\.)|screenshot-0\.' README.md README.en.md; then
  echo "README still references a legacy screenshot" >&2
  exit 1
fi

grep -q 'shanggqm/codexU' README.md || { echo "README.md is missing upstream attribution" >&2; exit 1; }
grep -q 'openclaw/openclaw' README.md || { echo "README.md is missing OpenClaw attribution" >&2; exit 1; }
grep -q 'NousResearch/hermes-agent' README.md || { echo "README.md is missing Hermes attribution" >&2; exit 1; }

if grep -q 'SHA256.*PLACEHOLDER' "$NOTES"; then
  echo "Release notes still contain checksum placeholders" >&2
  exit 1
fi

for arch in arm64 x86_64; do
  dmg="dist/codexU-${VERSION}-mac-${arch}.dmg"
  checksum="${dmg}.sha256"
  [[ -f "$dmg" && -f "$checksum" ]] || { echo "Missing $arch release assets" >&2; exit 1; }
  shasum -a 256 -c "$checksum"
  hash="$(awk '{print $1}' "$checksum")"
  grep -q "$hash" "$NOTES" || { echo "$arch checksum is missing from $NOTES" >&2; exit 1; }
done

plutil -lint Resources/Info.plist
git diff --check

if [[ "${ALLOW_EXISTING_RELEASE:-0}" != "1" ]]; then
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Local tag already exists: $TAG" >&2
    exit 1
  fi

  if git ls-remote --exit-code --tags "$RELEASE_REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "Remote tag already exists: $TAG" >&2
    exit 1
  fi

  if command -v gh >/dev/null && gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    echo "GitHub Release already exists: $TAG" >&2
    exit 1
  fi
fi

echo "Release metadata and assets are ready for $TAG"
