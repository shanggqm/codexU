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
- `~/.openclaw/agents/codex/agent/codex-home/state_5.sqlite` and its rollout token metadata for Codex executions invoked by OpenClaw
- `~/.openclaw/agents/main/sessions/*.jsonl` assistant `message.usage` and `toolCall` metadata
- `~/.openclaw/workspace/memory/tasks.json` and the local OpenClaw session index
- optional `~/Library/Caches/codexU/update-check.json` for cached GitHub Release update metadata

It should not upload local usage, transcript, task, thread, account, or path data to a third-party service. OpenClaw transcript parsing must not store prompt text, assistant response text, tool arguments, or tool output.

## Network Scope

codexU is local-first. Automatic update checks are disabled in this custom build. The update checker may request public GitHub Release metadata from `https://api.github.com/repos/shanggqm/codexU/releases` only when the user manually checks for updates.

The optional “Open in Codex” action only accepts canonical UUID thread IDs and opens the locally registered `codex://threads/<thread-id>` URL. It does not accept arbitrary schemes, paths, or user-provided URLs.

Update requests must not include local usage, transcript, task, thread, account, path, prompt, response, tool argument, or tool output data. The update checker may send standard HTTPS headers such as `User-Agent` and `If-None-Match` for ETag caching.

codexU must not silently download, install, replace, or relaunch the app as part of the GitHub Release check. It may open the user's default browser to a matching DMG asset or the Release page.
