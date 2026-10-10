#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${1:-}" != "--skip-build" ]]; then
    make build >/dev/null
fi
build/codexU.app/Contents/MacOS/codexU --self-test-home-startup
