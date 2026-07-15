# Codex usage and remaining limit notes

Date checked: 2026-07-13.

## Official model

Codex has two materially different accounting paths:

- ChatGPT sign-in: Codex usage follows the ChatGPT workspace, plan, RBAC, retention, and residency settings. The plan exposes usage limits and credits through ChatGPT/Codex account surfaces.
- API key sign-in: Codex usage follows the OpenAI Platform organization and standard API token pricing.

Official Codex pages used:

- https://developers.openai.com/codex/pricing
- https://developers.openai.com/codex/auth
- https://developers.openai.com/codex/app-server
- https://developers.openai.com/codex/cli/slash-commands
- https://developers.openai.com/codex/app/settings

## Account remaining limit

The stable-looking local path is Codex app-server JSON-RPC:

1. Start `codex app-server` over stdio.
2. Send `initialize` with `capabilities.experimentalApi = true`.
3. Send `initialized`.
4. Call:
   - `account/read`
   - `account/rateLimits/read`
   - `account/usage/read`

The generated schema for the installed Codex 0.144.2 runtime includes:

- `GetAccountRateLimitsResponse`
- `RateLimitSnapshot`
- `RateLimitWindow`
- `GetAccountTokenUsageResponse`
- `AccountTokenUsageSummary`

`account/rateLimits/read` returns rolling windows as percentages, not absolute token quota numbers. The response uses nullable `primary` and `secondary` transport slots. Those slot names do not define a fixed 5-hour or 7-day meaning; clients must classify each returned window by `windowDurationMins`.

Observed response combinations on this machine include:

- primary: 300 minutes, secondary: 10080 minutes
- primary: 10080 minutes, secondary: null
- each window has `usedPercent` and `resetsAt`

The widget therefore normalizes all returned slots before exposing quota data to the UI:

- 300 minutes: 5-hour quota
- 10080 minutes: 7-day quota
- missing, duplicate, or unknown durations: left unclassified and never labeled as 5-hour or 7-day quota

So this widget computes account remaining limit as:

```text
remainingPercent = 100 - usedPercent
```

That is a real account-limit percentage from Codex, but it is not an absolute number of turns, messages, or tokens.

## Local token usage

Codex keeps local thread inventory in `~/.codex/state_5.sqlite`. The `threads` table has a `tokens_used` column. This widget uses it for local historical usage:

- lifetime: sum of all `threads.tokens_used`
- today: sum where `threads.updated_at` is after local day start
- last 7 days: sum where `threads.updated_at` is in the current local 7-day window

This is useful for local activity tracking, but it is not the authoritative remaining account quota. A thread can be updated later, so daily grouping is an approximation based on last update time.

## Detailed local token usage

Codex session JSONL files under `~/.codex/sessions/**/rollout-*.jsonl` and `~/.codex/archived_sessions/*.jsonl` include `event_msg` records with `payload.type = token_count`. Those records expose:

- `input_tokens`
- `cached_input_tokens`
- `output_tokens`
- `reasoning_output_tokens`
- `total_tokens`

The widget treats `cached_input_tokens` as a subset of input tokens. Cost estimation therefore uses:

```text
uncached_input = input_tokens - cached_input_tokens
estimated_cost =
  uncached_input / 1M * input_price
+ cached_input_tokens / 1M * cached_input_price
+ output_tokens / 1M * output_price
```

`reasoning_output_tokens` is shown only as a sub-detail of output and is not added again for cost.

The JSONL stream can contain repeated cumulative token snapshots, so the parser computes deltas from consecutive `total_token_usage` snapshots per session instead of summing every record directly. For daily and monthly buckets, each positive delta is assigned to the timestamp of its `token_count` event. This is more precise than grouping a whole thread by `threads.updated_at`, but it is still a local estimate rather than an official invoice.

## What this widget intentionally avoids

- It does not read `~/.codex/auth.json` token values.
- It does not call private ChatGPT web endpoints directly.
- It does not parse prompt or tool payloads from session logs; it filters only `token_count` event lines.

## Current implementation choice

The widget displays both kinds of data separately:

- Account limit remaining: from `account/rateLimits/read`
- Local token usage: from `threads.tokens_used`
- Detailed token split and API-equivalent value: from local JSONL `token_count` events, with SQLite as the source of session paths and model names.

If app-server is unavailable, the widget falls back to SQLite-only mode and marks account-limit data as unavailable.

## Claude Code local support

Claude Code does not expose the same local `account/rateLimits/read` app-server API as Codex. v0.4.0 therefore separates historical usage from active quota:

- Historical token usage: parsed from assistant `message.usage` fields in `~/.claude/projects/**/*.jsonl`.
- Cache split: `cache_creation_input_tokens` and `cache_read_input_tokens` are mapped into the widget's cached input bucket so existing UI cards can show uncached/cached/output splits.
- Project attribution: uses transcript `cwd` first, then best-effort decoding of the Claude project directory name.
- Tool usage: counts only `tool_use.name`; it does not retain tool arguments or output.
- Skill usage: uses explicit Skill attribution fields when present and the `Skill` tool name as a fallback.
- Task board: reads `~/.claude/tasks/**/*.json` status and subject fields.
- Active quota: optional `~/Library/Caches/codexU/claude-code/statusline-snapshot.json` with 5-hour and 7-day used percentages. Missing snapshots are shown as unavailable, and snapshots older than 15 minutes are marked stale.

Claude Code API-equivalent value is an estimate from a small built-in Claude model price table. Unknown models still contribute tokens, but their dollar value is omitted from the estimate.
