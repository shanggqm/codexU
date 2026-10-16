#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# CI can reuse the app built by its Build step.
if [[ "${1:-}" != "--skip-build" ]]; then
  make build
fi
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/codexu-window-close.XXXXXX")
ROOT=$(cd "$ROOT" && pwd -L)
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/home" "$ROOT/tmp"
export CFFIXED_USER_HOME="$ROOT/home"
export TMPDIR="$ROOT/tmp"

clang -fblocks -dynamiclib tests/window-close/BeepObserver.m \
  -framework AppKit -framework AudioToolbox -o "$ROOT/BeepObserver.dylib"
clang -fblocks -DBEEP_OBSERVER_CONTROL tests/window-close/BeepObserver.m \
  -framework AppKit -framework AudioToolbox -o "$ROOT/control"
export DYLD_INSERT_LIBRARIES="$ROOT/BeepObserver.dylib"
"$ROOT/control" > "$ROOT/control.log" 2>&1
cat "$ROOT/control.log"
[[ $(grep -c '^WINDOW_CLOSE_ALERT ' "$ROOT/control.log") -eq 2 ]] || {
  echo 'window close sound observer positive controls failed'; exit 1;
}

APP=build/codexU.app/Contents/MacOS/codexU
for mode in background exit; do
  args=(--self-test-window-close)
  if [[ "$mode" == exit ]]; then args+=(--verify-window-close-exit); fi
  "$APP" "${args[@]}" > "$ROOT/$mode.log" 2>&1 || {
    cat "$ROOT/$mode.log"; exit 1;
  }
  cat "$ROOT/$mode.log"
  grep -q '^WINDOW_CLOSE_OBSERVER_LOADED$' "$ROOT/$mode.log"
  if grep -Eq 'WINDOW_CLOSE_ALERT|self-test failed' "$ROOT/$mode.log"; then exit 1; fi
  if [[ "$mode" == exit ]]; then
    grep -q 'requesting real application termination' "$ROOT/$mode.log"
  else
    grep -q 'window close self-test passed' "$ROOT/$mode.log"
  fi
done
echo 'window close integration tests passed: background, real exit, no additional alert sounds'
