#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

make build >/dev/null

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/.claude/projects/-tmp-claude-fixture"
CACHE_DIR="$TMP_DIR/cache"
mkdir -p "$PROJECT_DIR" "$CACHE_DIR/claude-code"
cp tests/fixtures/claude-code-session.jsonl "$PROJECT_DIR/session.jsonl"
PATH=/usr/bin:/bin /usr/bin/ruby -e 'time = Time.at(1_783_954_496, 492_086); File.utime(time, time, ARGV[0])' "$PROJECT_DIR/session.jsonl"

cat > "$CACHE_DIR/claude-code/statusline-snapshot.json" <<'JSON'
{
  "schemaVersion": 1,
  "capturedAt": "2026-07-07T07:00:00.000Z",
  "rateLimits": {
    "fiveHour": {
      "usedPercentage": 25,
      "resetsAt": "2026-07-07T10:00:00.000Z"
    },
    "sevenDay": {
      "usedPercentage": 40,
      "resetsAt": "2026-07-14T07:00:00.000Z"
    }
  }
}
JSON

OUTPUT="$TMP_DIR/out.json"
CODEXU_HOME_OVERRIDE="$TMP_DIR" \
CODEXU_CACHE_OVERRIDE="$CACHE_DIR" \
CODEXU_RUNTIME_FILTER="claude-code" \
  build/codexU.app/Contents/MacOS/codexU --dump-json > "$OUTPUT"

grep -q '"schemaVersion" : 2' "$OUTPUT"
grep -q '"id" : "claude-code"' "$OUTPUT"
grep -q '"name" : "Read"' "$OUTPUT"
grep -q '"remainingPercent" : 75' "$OUTPUT"
grep -q '"visibleTotalTokens" : 1900' "$OUTPUT"

CACHE_FILE="$CACHE_DIR/claude-code/session-usage-v1.json"
grep -q '"version":2' "$CACHE_FILE"

# Recreate the production failure path: a v1 cache stored every Date with
# second precision, while the source file keeps a fractional mtime. The v2
# reader must migrate this cache without opening the transcript again.
PATH=/usr/bin:/bin /usr/bin/ruby -rjson -rtime -e '
  path = ARGV.fetch(0)
  cache = JSON.parse(File.read(path))
  cache["version"] = 1
  cache.fetch("entries").each_value do |entry|
    nanoseconds = entry.delete("modificationTimeNanoseconds")
    entry["modificationDate"] = Time.at(nanoseconds / 1_000_000_000.0).utc.iso8601
    summary = entry.fetch("summary")
    summary["lastActiveAt"] = Time.at(summary["lastActiveAt"] / 1_000.0).utc.iso8601 if summary["lastActiveAt"]
    summary.fetch("deltas", []).each do |delta|
      delta["date"] = Time.at(delta.fetch("date") / 1_000.0).utc.iso8601
    end
    summary.fetch("skillLoads", []).each do |load|
      load["date"] = Time.at(load["date"] / 1_000.0).utc.iso8601 if load["date"]
    end
  end
  File.write(path, JSON.generate(cache))
' "$CACHE_FILE"

chmod 000 "$PROJECT_DIR/session.jsonl"
MIGRATED_OUTPUT="$TMP_DIR/out-migrated.json"
CODEXU_HOME_OVERRIDE="$TMP_DIR" \
CODEXU_CACHE_OVERRIDE="$CACHE_DIR" \
CODEXU_RUNTIME_FILTER="claude-code" \
  build/codexU.app/Contents/MacOS/codexU --dump-json > "$MIGRATED_OUTPUT"

grep -q '"visibleTotalTokens" : 1900' "$MIGRATED_OUTPUT"
grep -q '"version":2' "$CACHE_FILE"

# A subsequent warm load must also leave the migrated cache untouched.
FIRST_CACHE_MTIME="$(stat -f %m "$CACHE_FILE")"
sleep 1
WARM_OUTPUT="$TMP_DIR/out-warm.json"
CODEXU_HOME_OVERRIDE="$TMP_DIR" \
CODEXU_CACHE_OVERRIDE="$CACHE_DIR" \
CODEXU_RUNTIME_FILTER="claude-code" \
  build/codexU.app/Contents/MacOS/codexU --dump-json > "$WARM_OUTPUT"

grep -q '"visibleTotalTokens" : 1900' "$WARM_OUTPUT"
test "$FIRST_CACHE_MTIME" = "$(stat -f %m "$CACHE_FILE")"

echo "parser fixture checks passed"
