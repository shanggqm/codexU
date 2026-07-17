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

CODEX_HOME="$TMP_DIR/codex-home"
CODEX_CACHE="$TMP_DIR/codex-cache"
CODEX_ROLLOUT="$CODEX_HOME/.codex/sessions/2026/07/16/rollout-fixture.jsonl"
FAKE_CODEX="$TMP_DIR/fake-codex"
mkdir -p "$(dirname "$CODEX_ROLLOUT")" "$CODEX_CACHE"
cp tests/fixtures/codex-session-nonmonotonic.jsonl "$CODEX_ROLLOUT"

cat > "$FAKE_CODEX" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
while IFS= read -r line; do
  id="$(printf '%s' "$line" | jq -r '.id // empty')"
  case "$id" in
    1)
      printf '%s\n' '{"id":1,"result":{}}'
      ;;
    2)
      printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"pro","email":null}}}'
      ;;
    3)
      printf '%s\n' '{"id":3,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1784785418},"secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"}}}}'
      ;;
    4)
      printf '%s\n' '{"id":4,"result":{"summary":{"lifetimeTokens":123456789,"peakDailyTokens":457746130},"dailyUsageBuckets":[{"startDate":"2026-07-15","tokens":120000000},{"startDate":"2026-07-16","tokens":457746130}]}}'
      ;;
  esac
done
SH
chmod +x "$FAKE_CODEX"

sqlite3 "$CODEX_HOME/.codex/state_5.sqlite" <<SQL
CREATE TABLE threads (
  id TEXT PRIMARY KEY,
  rollout_path TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  cwd TEXT NOT NULL,
  title TEXT NOT NULL,
  tokens_used INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0,
  archived_at INTEGER,
  first_user_message TEXT NOT NULL DEFAULT '',
  preview TEXT NOT NULL DEFAULT '',
  recency_at INTEGER NOT NULL DEFAULT 0,
  model TEXT
);
INSERT INTO threads VALUES (
  '00000000-0000-4000-8000-000000000001',
  '$CODEX_ROLLOUT',
  1784163600,
  1784163720,
  '/tmp/codex-fixture',
  'Codex token regression fixture',
  1630,
  0,
  NULL,
  '',
  '',
  1784163720,
  'gpt-5.6'
);
SQL

CODEX_OUTPUT="$TMP_DIR/out-codex.json"
CODEXU_HOME_OVERRIDE="$CODEX_HOME" \
CODEXU_CACHE_OVERRIDE="$CODEX_CACHE" \
CODEXU_RUNTIME_FILTER="codex" \
CODEXU_CODEX_EXECUTABLE_OVERRIDE="$FAKE_CODEX" \
  "$APP_EXECUTABLE" --dump-json > "$CODEX_OUTPUT"

CODEX_DETAILED_TOTAL="$(
  jq -r '.runtimes[] | select(.scope == "codex") | .snapshot.local.detailedUsage.lifetime.tokens.visibleTotalTokens' \
    "$CODEX_OUTPUT"
)"
test "$CODEX_DETAILED_TOTAL" = "1630"
test "$(jq -r '.runtimes[] | select(.scope == "codex") | .snapshot.cloudLifetimeTokens' "$CODEX_OUTPUT")" = "123456789"
test "$(jq -r '.compat.codex.cloudLifetimeTokens' "$CODEX_OUTPUT")" = "123456789"
test "$(jq -r '.runtimes[] | select(.scope == "codex") | .snapshot.cloudUsageTrend.latestBucket.tokens' "$CODEX_OUTPUT")" = "457746130"
test "$(jq -r '.runtimes[] | select(.scope == "codex") | .snapshot.cloudUsageTrend.sourceQuality' "$CODEX_OUTPUT")" = "official"
grep -q '"tokenEventCount" : 3' "$CODEX_OUTPUT"

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
    "created": "2026-07-15 09:30",
    "deadline": "2026-07-31",
    "description": "根因: 根因:Parser fixture task summary\n如何: Verify structured extraction",
    "details": "Verify OpenClaw task attribution",
    "progress_percent": 42,
    "priority": "high",
    "source": "local",
    "status": "in_progress",
    "title": "OpenClaw parser fixture"
  },
  {
    "id": "task-fixture-stale",
    "created": "2026-06-01 09:00",
    "updatedAt": "2027-01-01T00:00:00Z",
    "deadline": "2026-12-31",
    "description": "A stale task with a future deadline",
    "priority": "high",
    "source": "local",
    "status": "in_progress",
    "title": "Stale OpenClaw parser fixture"
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
jq -e '
  [.runtimes[] | select(.scope == "openClaw") | .snapshot.taskBoard.columns[].items[]
    | select(.id == "openclaw-task-task-fixture-1")][0]
  | .createdAt != null
    and .updatedAt == .createdAt
    and .createdHasTime == true
    and .deadlineAt != null
    and .deadlineHasTime == false
    and .progressPercent == 42
    and .progressOrigin == "explicit"
' "$OUTPUT" >/dev/null
jq -e '
  [.runtimes[] | select(.scope == "openClaw") | .snapshot.taskBoard.columns[]
    | select(.id == "active") | .items[].id] as $ids
  | ($ids | index("openclaw-task-task-fixture-1"))
      < ($ids | index("openclaw-task-task-fixture-stale"))
' "$OUTPUT" >/dev/null

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

echo "Codex, OpenClaw, Claude Code, and Hermes parser fixture checks passed"
