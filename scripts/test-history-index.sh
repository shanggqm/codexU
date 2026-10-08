#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ "${CODEXU_SKIP_BUILD:-0}" != 1 ]]; then make build; fi
APP=build/codexU.app/Contents/MacOS/codexU
for suite in history-index token-counter statistics-time-zone model-inference-performance leadership-model home-startup home-snapshot home-task-reader runtime-fast-sources; do
  "$APP" "--self-test-$suite"
done
echo "Component checks passed; this does not certify full indexing or native startup acceptance."
