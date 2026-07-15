#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
make build
"build/codexU.app/Contents/MacOS/codexU" --self-test-palettes
