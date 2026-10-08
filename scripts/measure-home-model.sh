#!/usr/bin/env bash
# Measures process/model availability only. It does not measure native rendering or interaction.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SAMPLES="${1:-30}"
ARTIFACT_DIR="$ROOT_DIR/.local-artifacts/feature010"
mkdir -p "$ARTIFACT_DIR"
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codexu-model-probe.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT
cp build/codexU.app/Contents/MacOS/codexU "$PROBE_DIR/codexU"
python3 - "$PROBE_DIR/codexU" "$ARTIFACT_DIR/model-startup.json" "$SAMPLES" <<'PY'
import json, pathlib, subprocess, sys, time
executable, destination, count = sys.argv[1], pathlib.Path(sys.argv[2]), int(sys.argv[3])
if not 1 <= count <= 1000:
    raise SystemExit('sample count must be between 1 and 1000')
results = []
for index in range(count):
    start = time.monotonic()
    try:
        process = subprocess.run([executable, '--probe-home'], capture_output=True, text=True, timeout=20)
        result = json.loads(process.stdout)
        result['exitCode'] = process.returncode
    except Exception as error:
        result = {'error': type(error).__name__, 'exitCode': -1}
    result.update(sample=index + 1, processSeconds=time.monotonic() - start)
    results.append(result)
    destination.write_text(json.dumps(results, indent=2))
failed = sum(result['exitCode'] != 0 or result['processSeconds'] > 5 for result in results)
print(json.dumps({'samples': count, 'failures': failed,
                  'maxProcessSeconds': max(result['processSeconds'] for result in results),
                  'nativeDrawingMeasured': False}))
raise SystemExit(1 if failed else 0)
PY
