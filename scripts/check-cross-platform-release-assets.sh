#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)}"
DIST_ROOT="${2:-dist}"
VERSION="${VERSION#v}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 1
fi

mac_asset() {
  printf '%s/%s' "$DIST_ROOT" "codexU-${VERSION}-mac-$1.dmg"
}

windows_asset() {
  local windows_root="$DIST_ROOT/windows"
  local name="$1"
  if [[ -f "$windows_root/$name" ]]; then
    printf '%s/%s' "$windows_root" "$name"
  else
    printf '%s/%s' "$DIST_ROOT" "$name"
  fi
}

ASSETS=(
  "$(mac_asset arm64)"
  "$(mac_asset x86_64)"
  "$(windows_asset "codexU-${VERSION}-windows-x86_64.msi")"
  "$(windows_asset "codexU-${VERSION}-windows-x86_64-setup.exe")"
)

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print tolower($1)}'
  else
    sha256sum "$1" | awk '{print tolower($1)}'
  fi
}

for asset in "${ASSETS[@]}"; do
  checksum="$asset.sha256"
  [[ -f "$asset" ]] || { echo "Missing release asset: $asset" >&2; exit 1; }
  [[ -f "$checksum" ]] || { echo "Missing checksum: $checksum" >&2; exit 1; }
  expected="$(awk 'NF {print tolower($1); exit}' "$checksum")"
  actual="$(hash_file "$asset")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid checksum file: $checksum" >&2; exit 1; }
  [[ "$expected" == "$actual" ]] || {
    echo "Checksum mismatch: $asset" >&2
    exit 1
  }
  echo "verified: $asset"
done

echo "Cross-platform release assets verified for codexU $VERSION"
