#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)}"
TAG="v${VERSION}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
NOTES="docs/release-notes-v${VERSION}.md"

[[ "$VERSION" == "$PLIST_VERSION" ]] || { echo "Info.plist version mismatch" >&2; exit 1; }
[[ -f "$NOTES" ]] || { echo "Missing release notes: $NOTES" >&2; exit 1; }
grep -q "## ${VERSION} -" CHANGELOG.md || { echo "CHANGELOG is missing $VERSION" >&2; exit 1; }
grep -q "codexU-${VERSION}-mac-arm64.dmg" README.md || { echo "README.md artifact examples are stale" >&2; exit 1; }
grep -q "codexU-${VERSION}-mac-arm64.dmg" README.en.md || { echo "README.en.md artifact examples are stale" >&2; exit 1; }

if grep -q 'SHA256_PLACEHOLDER' "$NOTES"; then
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

  if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "Remote tag already exists: $TAG" >&2
    exit 1
  fi

  if command -v gh >/dev/null && gh release view "$TAG" >/dev/null 2>&1; then
    echo "GitHub Release already exists: $TAG" >&2
    exit 1
  fi
fi

echo "Release metadata and assets are ready for $TAG"
