# Security Policy

## Supported Versions

The latest version on the default branch is the supported version.

## Reporting A Vulnerability

Please report security issues privately instead of opening a public issue when the report includes account data, local file paths, thread titles, local Codex database contents, or other sensitive information.

Include:

- macOS version.
- codexU version.
- Whether the issue affects app launch, local file reads, quota reads, packaging, or update distribution.
- Minimal reproduction steps without private Codex data.

## Local Data Scope

codexU reads:

- `~/.codex/state_5.sqlite`
- `~/.codex/automations/**/automation.toml`
- local responses from `codex app-server`
- `~/.codex/sessions/**/rollout-*.jsonl` and `~/.codex/archived_sessions/*.jsonl` token metadata
- `~/.claude/projects/**/*.jsonl` assistant `message.usage` and `tool_use.name` metadata
- `~/.claude/tasks/**/*.json` task status/title metadata
- optional `~/Library/Caches/codexU/claude-code/statusline-snapshot.json`
- optional `~/Library/Caches/codexU/update-check.json` for cached GitHub Release update metadata
- optional CLI Proxy API management key stored as a generic password in macOS Keychain

It should not upload local usage, transcript, task, thread, account, or path data to a third-party service. Claude Code transcript parsing must not store prompt text, assistant response text, tool arguments, or tool output.

## Network Scope

codexU is local-first. The update checker may request public GitHub Release metadata from `https://api.github.com/repos/shanggqm/codexU/releases` during automatic checks when enabled or when the user manually checks for updates.

When the user explicitly enables CLI Proxy API quota support, codexU may request the user-configured CPA server:

- `GET /v0/management/auth-files` to enumerate enabled Codex credentials and obtain opaque `auth_index` values.
- `POST /v0/management/api-call` to ask CPA to query `https://chatgpt.com/backend-api/wham/usage` with the selected CPA credential.

These requests contain the CPA management key, the selected opaque `auth_index`, the upstream quota URL, and the documented `$TOKEN$` placeholder. They must not contain local usage, transcript, task, thread, path, prompt, response, tool argument, tool output, or raw log data. CPA resolves the upstream token on the server; codexU must not receive, store, or print that token.

Remote CPA URLs must use HTTPS. Plain HTTP is accepted only for loopback hosts (`localhost`, `127.0.0.1`, and `::1`). The management key is stored in macOS Keychain and must not be written to `UserDefaults`, diagnostics, source labels, or JSON dump output. Account email addresses returned by CPA must be masked before entering the displayed or dumped snapshot.

Update requests must not include local usage, transcript, task, thread, account, path, prompt, response, tool argument, or tool output data. The update checker may send standard HTTPS headers such as `User-Agent` and `If-None-Match` for ETag caching.

codexU must not silently download, install, replace, or relaunch the app as part of the GitHub Release check. It may open the user's default browser to a matching DMG asset or the Release page.
