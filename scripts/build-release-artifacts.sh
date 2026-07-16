#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"

if [[ "$VERSION" != "$PLIST_VERSION" ]]; then
  echo "Requested version $VERSION does not match Info.plist version $PLIST_VERSION" >&2
  exit 1
fi

plutil -lint Resources/Info.plist
git diff --check

make build SWIFT_OPT_FLAGS=-Onone >/dev/null
build/codexU.app/Contents/MacOS/codexU --self-test-statistics-time-zone
build/codexU.app/Contents/MacOS/codexU --self-test-status-item
build/codexU.app/Contents/MacOS/codexU --self-test-rate-limits
build/codexU.app/Contents/MacOS/codexU --self-test-particle-animation
build/codexU.app/Contents/MacOS/codexU --self-test-updates
build/codexU.app/Contents/MacOS/codexU --self-test-task-navigation
build/codexU.app/Contents/MacOS/codexU --self-test-local-system
build/codexU.app/Contents/MacOS/codexU --self-test-agent-selection
build/codexU.app/Contents/MacOS/codexU --self-test-codex-token-events
CODEXU_SKIP_BUILD=1 ./scripts/test-parsers.sh

make release-all

verify_asset() {
  local arch="$1"
  local expected_arch="$2"
  local dmg="dist/codexU-${VERSION}-mac-${arch}.dmg"
  local checksum="${dmg}.sha256"
  local mount_dir

  [[ -f "$dmg" ]] || { echo "Missing release asset: $dmg" >&2; exit 1; }
  [[ -f "$checksum" ]] || { echo "Missing checksum: $checksum" >&2; exit 1; }
  shasum -a 256 -c "$checksum"
  hdiutil verify "$dmg" >/dev/null

  mount_dir="$(mktemp -d)"
  hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$dmg" >/dev/null
  file "$mount_dir/codexU.app/Contents/MacOS/codexU" | grep -q "$expected_arch"
  codesign --verify --deep --strict "$mount_dir/codexU.app"
  if [[ "$arch" == "arm64" ]]; then
    "$mount_dir/codexU.app/Contents/MacOS/codexU" --self-test-agent-selection
    "$mount_dir/codexU.app/Contents/MacOS/codexU" --self-test-task-navigation
    "$mount_dir/codexU.app/Contents/MacOS/codexU" --self-test-local-system
    "$mount_dir/codexU.app/Contents/MacOS/codexU" --self-test-codex-token-events
    CODEXU_SKIP_BUILD=1 \
    CODEXU_APP_EXECUTABLE="$mount_dir/codexU.app/Contents/MacOS/codexU" \
      ./scripts/test-parsers.sh
  fi
  hdiutil detach "$mount_dir" >/dev/null
  rmdir "$mount_dir"
}

verify_asset arm64 arm64
verify_asset x86_64 x86_64

echo "Release artifacts verified for codexU $VERSION"
cat "dist/codexU-${VERSION}-mac-arm64.dmg.sha256"
cat "dist/codexU-${VERSION}-mac-x86_64.dmg.sha256"
