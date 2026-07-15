#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${CODEXU_SKIP_BUILD:-0}" != "1" ]]; then
  make build >/dev/null
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SESSIONS_DIR="$TMP_DIR/.openclaw/agents/main/sessions"
TASKS_DIR="$TMP_DIR/.openclaw/workspace/memory"
CACHE_DIR="$TMP_DIR/cache"
mkdir -p "$SESSIONS_DIR" "$TASKS_DIR" "$CACHE_DIR/openclaw"
cp tests/fixtures/openclaw-session.jsonl "$SESSIONS_DIR/fixture-session.jsonl"

printf '%s\n' '{
  "agent:main:fixture": {
    "status": "active",
    "sessionId": "fixture-session",
    "sessionFile": "'"$SESSIONS_DIR"'/fixture-session.jsonl",
    "updatedAt": "2026-07-15T01:00:02.000Z",
    "modelProvider": "openai",
    "model": "gpt-5.4",
    "channel": "local",
    "totalTokens": 1900
  }
}' > "$SESSIONS_DIR/sessions.json"

printf '%s\n' '[
  {
    "id": "task-fixture-1",
    "created": "2026-07-15T01:00:00.000Z",
    "description": "Parser fixture task summary",
    "details": "Verify OpenClaw task attribution",
    "priority": "high",
    "source": "local",
    "status": "in_progress",
    "title": "OpenClaw parser fixture"
  }
]' > "$TASKS_DIR/tasks.json"

OUTPUT="$TMP_DIR/out.json"
CODEXU_HOME_OVERRIDE="$TMP_DIR" \
CODEXU_CACHE_OVERRIDE="$CACHE_DIR" \
CODEXU_RUNTIME_FILTER="openclaw" \
  build/codexU.app/Contents/MacOS/codexU --dump-json > "$OUTPUT"

grep -q '"schemaVersion" : 2' "$OUTPUT"
grep -q '"id" : "openclaw"' "$OUTPUT"
grep -q '"name" : "Read"' "$OUTPUT"
grep -q '"visibleTotalTokens" : 1900' "$OUTPUT"
grep -q '"source" : "openclaw"' "$OUTPUT"
grep -q '"hasSummary" : true' "$OUTPUT"

CACHE_FILE="$CACHE_DIR/openclaw/session-usage-v1.json"
grep -q '"version":1' "$CACHE_FILE"

FIRST_CACHE_MTIME="$(stat -f %m "$CACHE_FILE")"
sleep 1
WARM_OUTPUT="$TMP_DIR/out-warm.json"
CODEXU_HOME_OVERRIDE="$TMP_DIR" \
CODEXU_CACHE_OVERRIDE="$CACHE_DIR" \
CODEXU_RUNTIME_FILTER="openclaw" \
  build/codexU.app/Contents/MacOS/codexU --dump-json > "$WARM_OUTPUT"

grep -q '"visibleTotalTokens" : 1900' "$WARM_OUTPUT"
test "$FIRST_CACHE_MTIME" = "$(stat -f %m "$CACHE_FILE")"

echo "OpenClaw parser fixture checks passed"
