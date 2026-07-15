#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_EXECUTABLE="${CODEXU_APP_EXECUTABLE:-build/codexU.app/Contents/MacOS/codexU}"

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
  "$APP_EXECUTABLE" --dump-json > "$OUTPUT"

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
  "$APP_EXECUTABLE" --dump-json > "$WARM_OUTPUT"

grep -q '"visibleTotalTokens" : 1900' "$WARM_OUTPUT"
test "$FIRST_CACHE_MTIME" = "$(stat -f %m "$CACHE_FILE")"

CLAUDE_HOME="$TMP_DIR/claude-home"
CLAUDE_CACHE="$TMP_DIR/claude-cache"
mkdir -p "$CLAUDE_HOME/.claude/projects/fixture" "$CLAUDE_CACHE"
cp tests/fixtures/claude-code-session.jsonl "$CLAUDE_HOME/.claude/projects/fixture/fixture-session.jsonl"

CLAUDE_OUTPUT="$TMP_DIR/out-claude.json"
CODEXU_HOME_OVERRIDE="$CLAUDE_HOME" \
CODEXU_CACHE_OVERRIDE="$CLAUDE_CACHE" \
CODEXU_RUNTIME_FILTER="claude-code" \
  "$APP_EXECUTABLE" --dump-json > "$CLAUDE_OUTPUT"

grep -q '"id" : "claude-code"' "$CLAUDE_OUTPUT"
grep -q '"displayName" : "Claude Code"' "$CLAUDE_OUTPUT"
grep -q '"visibleTotalTokens" : 1900' "$CLAUDE_OUTPUT"
grep -q '"name" : "Read"' "$CLAUDE_OUTPUT"

HERMES_HOME="$TMP_DIR/hermes-home"
HERMES_CACHE="$TMP_DIR/hermes-cache"
mkdir -p "$HERMES_HOME/.hermes" "$HERMES_CACHE"
sqlite3 "$HERMES_HOME/.hermes/state.db" <<'SQL'
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  source TEXT,
  model TEXT,
  billing_provider TEXT,
  title TEXT,
  cwd TEXT,
  started_at REAL,
  ended_at REAL,
  archived INTEGER,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cache_read_tokens INTEGER,
  cache_write_tokens INTEGER,
  reasoning_tokens INTEGER,
  actual_cost_usd REAL,
  estimated_cost_usd REAL,
  message_count INTEGER,
  tool_call_count INTEGER
);
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  session_id TEXT,
  timestamp REAL,
  tool_name TEXT
);
INSERT INTO sessions VALUES (
  'hermes-native', 'cli', 'hermes-3', 'nous', 'Native Hermes fixture', '/tmp/hermes-fixture',
  1784077200, 1784077260, 0, 1000, 400, 200, 100, 50, 0.25, 0.25, 2, 1
);
INSERT INTO sessions VALUES (
  'hermes-codex-backed', 'cli', 'codex/gpt-5', 'openai-codex', 'Codex-backed fixture', '/tmp/hermes-fixture',
  1784077300, 1784077360, 0, 9999, 9999, 0, 0, 0, 1.00, 1.00, 1, 0
);
INSERT INTO messages VALUES ('message-native', 'hermes-native', 1784077250, 'terminal');
SQL

HERMES_OUTPUT="$TMP_DIR/out-hermes.json"
CODEXU_HOME_OVERRIDE="$HERMES_HOME" \
CODEXU_CACHE_OVERRIDE="$HERMES_CACHE" \
CODEXU_RUNTIME_FILTER="hermes" \
  "$APP_EXECUTABLE" --dump-json > "$HERMES_OUTPUT"

grep -q '"id" : "hermes"' "$HERMES_OUTPUT"
grep -q '"displayName" : "Hermes"' "$HERMES_OUTPUT"
grep -q '"visibleTotalTokens" : 1700' "$HERMES_OUTPUT"
grep -q '"name" : "terminal"' "$HERMES_OUTPUT"
grep -q '"source" : "hermes"' "$HERMES_OUTPUT"
grep -q '"id" : "hermes:hermes-native"' "$HERMES_OUTPUT"
grep -q '"id" : "hermes:hermes-codex-backed"' "$HERMES_OUTPUT"
grep -q 'Codex-backed 会话已从 Hermes token 统计排除' "$HERMES_OUTPUT"
if grep -q '"visibleTotalTokens" : 19998' "$HERMES_OUTPUT"; then
  echo "Hermes parser incorrectly counted Codex-backed tokens" >&2
  exit 1
fi

echo "OpenClaw, Claude Code, and Hermes parser fixture checks passed"
