#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXPECTED_TARGET="13.0"
FAILURES=0

fail() {
  echo "macOS compatibility check failed: $1" >&2
  FAILURES=$((FAILURES + 1))
}

check_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

check_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "$file is missing: $expected"
}

check_not_contains() {
  local file="$1"
  local forbidden="$2"
  if grep -Fq -- "$forbidden" "$file"; then
    fail "$file still contains unsupported declaration: $forbidden"
  fi
}

make_target="$(sed -n 's/^DEPLOYMENT_TARGET ?= //p' Makefile)"
plist_target="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' Resources/Info.plist)"

check_equal "Makefile deployment target" "$make_target" "$EXPECTED_TARGET"
check_equal "Info.plist minimum system version" "$plist_target" "$EXPECTED_TARGET"
check_contains Makefile 'APPLE_SILICON_TARGET_TRIPLE ?= arm64-apple-macos$(DEPLOYMENT_TARGET)'
check_contains Makefile 'INTEL_TARGET_TRIPLE ?= x86_64-apple-macos$(DEPLOYMENT_TARGET)'
check_contains Makefile 'SWIFTC_FEATURE_FLAGS += -D CODEXU_HAS_LIQUID_GLASS'
check_contains Sources/CodexUsageWidget/main.swift '#if compiler(>=6.2) && CODEXU_HAS_LIQUID_GLASS'
check_contains README.md '- macOS 13 或更新版本。'
check_contains README.md 'TARGET_TRIPLE="x86_64-apple-macos13.0"'
check_contains README.en.md '- macOS 13 or later.'
check_contains README.en.md 'TARGET_TRIPLE="x86_64-apple-macos13.0"'
check_contains DISTRIBUTION.md '- macOS 13 or later.'
check_contains DISTRIBUTION.md 'TARGET_TRIPLE="x86_64-apple-macos13.0"'
check_contains scripts/package-dmg.sh '- macOS 13 或更新版本。'

for file in README.md README.en.md DISTRIBUTION.md scripts/package-dmg.sh; do
  check_not_contains "$file" 'macOS 14'
  check_not_contains "$file" 'macos14.0'
done

if (( FAILURES > 0 )); then
  echo "$FAILURES macOS compatibility check(s) failed" >&2
  exit 1
fi

echo "macOS compatibility checks passed"
