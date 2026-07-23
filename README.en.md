# codexU

![codexU v1.2.0 AI Leadership assessment model](docs/screenshot-v1.2.0-ai-leadership.png)

## A First-of-Its-Kind AI Leadership Assessment Model

codexU v1.2.0 turns a new OPC question—how many AI workers one person can lead, how long they work, and how well they are orchestrated—into a local, explainable model that compounds over time. It combines real Codex and Claude Code worker records on one timeline, then produces a rolling 28-day score from four dimensions: management span, labor leverage, orchestration, and autonomous operation.

- **See the AI organization at a glance:** score, 28-day led agents, AI hours, and peak concurrency sit beside a live command-radius orbit driven by today's agents.
- **No token-based score inflation:** only locally verifiable or derived worker lifecycles, parent-child relationships, concurrency, and autonomous runs count. Unreliable cost, delivery, and estimated intervals stay outside the score.
- **Codex + Claude Code, evaluated together:** AI leadership represents the complete workforce you direct, without runtime filters or naïve addition of per-project peaks.
- **Seven memorable ranks:** a fixed 0–100 progression, seven badge identities, and a living orbit turn an explainable score into a recognizable growth marker.
- **Local and private:** evaluation stays on your Mac and does not upload usage, threads, paths, logs, or account data.

> [!IMPORTANT]
> **Upgrade to v1.2.0 or later.** v1.2.0 introduces the local AI Leadership assessment model while retaining the Codex branch token deduplication fix from v1.1.5. [Download the latest release](https://github.com/shanggqm/codexU/releases/latest).

codexU is a macOS menu bar and desktop app for tracking OpenAI Codex / ChatGPT Codex and Claude Code quota, token usage, today's tasks, and local AI leadership. It keeps the information you check most in the menu bar and main window, so you can quickly see remaining quota, reset times, daily progress, and how much AI labor one person is directing.

![codexU v1.1.0 palette gallery, settings, and main window](docs/screenshot-v1.1.0-palette-gallery.png)

## Who It Is For

- Developers who use OpenAI Codex, Codex CLI, or the Codex desktop app every day.
- Developers who use both Codex and Claude Code and want one local view for both runtimes.
- ChatGPT Pro / Team users who want a quick view of Codex 5-hour quota, 7-day quota, token usage, and reset times.
- macOS users who want to check Codex status without repeatedly opening a browser or terminal.

## Features

- Includes six controlled palettes—Default, Blue-and-White Porcelain, Forbidden City Red, Thousand Li Landscape, Dunhuang Apsara, and Orchid Dawn—with instant preview and switching in a dedicated Liquid Glass gallery. Community palettes ship only after repository review, license checks, and CI rendering validation; arbitrary user-side installation is intentionally unsupported.
- Shows remaining and used Codex quota for the 5-hour and 7-day windows, including reset times; quota types are classified by their protocol-reported durations and trusted responses automatically select a single- or dual-quota layout.
- When Codex reports available rate-limit resets, the main quota area shows the total and the two earliest expiry details; hover reveals the complete list in the same tooltip used by Usage Trend. If the backend returns only a count, codexU explicitly marks the missing expiry details. Missing fields, zero resets, and unsupported Claude Code data stay hidden.
- Adds a menu bar runtime menu with separate Codex and Claude Code cards, 5-hour/7-day remaining quota, today's token usage, and total tokens today.
- Offers transparent Minimal, Classic, and Rich menu bar modes: Minimal keeps thicker quota rings, Classic keeps the quota number inside each progress ring, and Rich keeps full labels, bars, and reset times. A single active window automatically collapses to a single-quota layout.
- Preserves the full ring particle effect while rendering it only when the main window is visible, frontmost, and focused by default. Power Saving mode renders particles only while the ring is hovered, and animation stops in the background or under Low Power, thermal, and Reduce Motion constraints.
- Lets you switch menu bar quotas between used and remaining, choose 5-hour, 7-day or monthly, today tokens, and reset countdown, and keeps 5h/7d/mo progress colors aligned with the main blue-purple quota rings. Team monthly windows (for example 43800 minutes) are classified and shown correctly instead of being treated as unknown.
- Uses progress direction instead of extra labels: used runs clockwise/left-to-right, while remaining runs counterclockwise/right-to-left.
- Uses monochrome templates derived exactly from the original Runtime logos and resolves icon/text colors from the menu bar's effective appearance; branded color icons remain in the main window and popover.
- Shows today's total tokens as one vertically centered number in the menu bar, without an extra `T` label.
- Uses the system menu bar body size for today's total and a higher-contrast supporting foreground for 5h/7d labels and reset times while preserving hierarchy beneath primary values.
- Adds a top-level `Codex | Claude Code` switch in the main widget so all panels can switch runtime scope manually.
- Supports Claude Code local transcript usage, 7-day trends, project rankings, top tools/Skills, and a basic task board.
- Summarizes token usage for today, the last 7 days, and lifetime totals with uncached input, cached input, and output splits.
- Estimates the current month's API-equivalent value from OpenAI API token prices and shows progress against Plus, Pro 100, Pro 200, and the full monthly quota value. The bar uses a segmented nonlinear scale, so movement past Pro 200 remains visible and is not a linear dollar ratio.
- Leads the overview with a rank emblem and command-radius orbit for rolling 28-day AI leadership. The emblem stays locked to the orbit center, while score, 28-day led agents, 28-day AI hours, and peak concurrency form a 2×2 metric grid; orbit nodes continue to represent today's agents. The unchanged quota rings sit immediately to its right with an explicit Usage label.
- Adds lower dashboard tabs for today's tasks, AI leadership, usage trend, project ranking, and Skill usage. AI leadership always evaluates the combined Codex and Claude Code workforce; its detail view starts with the full badge path for every rank and places the score directly on the progress track, followed by four headline metrics, four dimensions, a daily AI-hours/agents/peak combo chart, and project contributions.
- Organizes today's tasks according to each factual source: Codex uses Recent, To continue, Scheduled, and Archived today; Claude Code uses explicit local task states for Active, Pending, Planned, and Completed. Recent activity and archival are not presented as proof of running or success.
- Task cards prioritize title, workspace, factual time, and trusted state. Automations show the next run only when it can be determined, and only cards with a valid session deep link expose whole-card click, hover, pointer, and keyboard-focus feedback.
- Codex Usage Trend shows a six-month daily token heatmap and a model activity overview with the top model, active days, active model count, and range daily average. Claude Code does not yet support model attribution and retains the existing 7-day summary.
- Adds a Codex-only model area chart with one color per visible model and a dashed total-usage line. It defaults to the last 30 days and can switch to 60, 90, or 180 days. It also summarizes the last-7-day total, daily average, and change versus the previous seven days. It shows the top eight models plus an "Other models" aggregate, and switches the y-axis between tokens and API-equivalent estimated cost. Models without a dedicated price are explicitly labeled as reference cost calculated with GPT-5.5 pricing. Cost mode is unavailable when the fallback thread source has no token split.
- Shows recent and all-time project rankings with tokens, estimated value, thread counts, and recent activity.
- Shows top tool calls and top Skill usage to explain the structure of local Codex work.
- Runs as a standard macOS window with a compact default layout, resizing from 820 to 1280 points without changing card order or information structure, and restoration of the previous window size. It supports Dock, system window controls, minimization, and optional background running after the main window is closed; closing the main window hides the Dock icon and keeps the menu bar item.
- Uses `Command + U` by default to show or hide the main window, and the shortcut can be customized in Settings. The menu bar runtime menu can also open the main window, open settings, or quit.
- Includes a Settings window for Chinese/English UI text, system/light/dark appearance, menu bar content with live preview, always-on-top behavior, close-window behavior, system status, and update check configuration.
- Checks GitHub Releases for newer versions by default, including beta releases, and offers the DMG that matches the current Mac architecture. It does not silently download or install updates, and automatic checks can be turned off.
- Reads data locally and does not upload usage, threads, or account data to a third-party service.

## Keyboard Shortcuts

- `Command + U`: shows or hides the main window by default and can be customized in Settings. If the window is minimized, the shortcut restores it and brings it forward.
- Custom combinations require at least two modifiers, including Command or Control; known high-risk system and accessibility shortcuts are rejected.
- Press Backspace while recording to clear the shortcut, or Escape to cancel; you can restore the default or record another shortcut later.
- The app detects conflicts with other exclusive hotkey registrations. macOS does not provide a complete query for nonexclusive registrations, so choose another combination if another app still conflicts.
- Menu bar gauge icon: opens the runtime menu. Clicking a Codex or Claude Code card opens the main widget with that runtime selected.
- Menu bar runtime menu: shows quick Codex / Claude Code status and provides Open, Settings, and Quit actions.
- Settings window: configure language, appearance, menu bar mode/quota direction/visible metrics, always-on-top and close-window behavior, and control automatic checks or manually check GitHub Releases from the System section.
- Main-window refresh button: immediately refresh quota, token usage, trend, and task board.
- System window controls: close, minimize, or zoom the main window. After closing, reopen from the menu bar item or shortcut; quit from the menu bar runtime menu or the app menu.

## First Install: Privacy & Security

codexU is distributed outside the Mac App Store. On first launch, macOS may block it until you manually allow it:

1. Open `codexU.app` once. If macOS says it cannot be opened, cancel the dialog.
2. Open **System Settings > Privacy & Security**.
3. In the **Security** section, click **Open Anyway** for `codexU.app`.
4. Confirm with Touch ID or your password, then click **Open**.

You can also right-click `codexU.app` in Finder and choose **Open**, then confirm the same security prompt.

codexU needs access to local Codex data under `~/.codex/`. When Claude Code stats are used, it also reads local transcripts, tasks, and status cache files under `~/.claude/`. If macOS asks for file or folder access, allow it so the widget can read local usage, threads, and automation metadata.

## Install

Download the DMG for your Mac architecture from GitHub Releases:

- Apple Silicon: `codexU-<version>-mac-arm64.dmg`
- Intel: `codexU-<version>-mac-x86_64.dmg`

1. Open the DMG.
2. Drag `codexU.app` into the `Applications` folder.
3. Open codexU from `Applications`.
4. Complete the **First Install: Privacy & Security** steps above if macOS blocks the first launch.

After installation, codexU checks GitHub Releases for new versions at most once per day by default, including beta releases. The check reads public release metadata only. When an update is available, codexU opens the browser to download the DMG or view the Release page; installation remains manual. You can turn off automatic checks or run a manual check from the System section in Settings.

## Requirements

- macOS 13 or later.
- A local Codex installation.
- A signed-in Codex account for quota data.
- Codex must have been used at least once so `~/.codex/state_5.sqlite` exists.
- Claude Code support is optional. Historical tokens come from `~/.claude/projects/**/*.jsonl`; quota requires a local statusLine snapshot cache.
- Xcode Command Line Tools for building from source.

## Build From Source

```sh
make build
```

Run the app:

```sh
make run
```

Install to `/Applications`:

```sh
make install
```

Inspect the data source output:

```sh
make probe
```

## Package A DMG

```sh
make release
```

`make release` builds a DMG for the current build machine architecture. You can also build explicit Mac architectures:

```sh
make release-arm64
make release-intel
make release-all
```

Release artifacts are written to `dist/`, for example:

```text
dist/codexU-1.2.0-mac-arm64.dmg
dist/codexU-1.2.0-mac-arm64.dmg.sha256
dist/codexU-1.2.0-mac-x86_64.dmg
dist/codexU-1.2.0-mac-x86_64.dmg.sha256
```

For Developer ID signing and notarization, see [DISTRIBUTION.md](DISTRIBUTION.md).

## Data Sources

- Account and quota: `codex app-server` JSON-RPC methods `account/read`, `account/rateLimits/read`, and `account/usage/read`.
- Local token totals: `~/.codex/state_5.sqlite`.
- Detailed token splits: `token_count` events in `~/.codex/sessions/**/rollout-*.jsonl` and `~/.codex/archived_sessions/*.jsonl`.
- Today's board: unarchived and archived Codex threads in the local SQLite database. The two-hour activity window means only “recent,” while archival does not imply running or success.
- Usage trends and project rankings: aggregated from local session `token_count` events. Model curves use the most recent preceding `turn_context.model` from the same session; a turn context without a model clears the prior attribution and falls back to the thread model. Daily attribution falls back to approximate thread-updated-time data when detailed events are unavailable. The Codex model area chart uses a top-eight-plus-other view with a dashed total-usage line and keeps cost values explicitly API-equivalent estimates. Claude Code does not yet expose model attribution or a model area chart.
- Tool and Skill usage: tool call and Skill load records parsed from local session events.
- Scheduled tasks: enabled automation metadata under `~/.codex/automations/**/automation.toml`. The next run is computed locally only when cadence, timezone, and time are sufficiently explicit.
- AI leadership: Codex reads only local thread relationships and structural `task_started` / `task_complete` events; Claude Code reads only `turn_duration` and subagent lifecycles. ScoreModel v1.3 scores only factual or derived intervals across span, leverage, orchestration, and autonomy. Estimated intervals are excluded, while evidence confidence is shown separately and does not multiply the score.
- Claude Code historical tokens: assistant `message.usage` fields in `~/.claude/projects/**/*.jsonl`.
- Claude Code tools, Skills, and tasks: transcript `tool_use.name` / explicit Skill attribution, plus `~/.claude/tasks/**/*.json`. When a Skill path is absent, codexU infers it from Claude Code's current personal, project, nested, plugin, and legacy-command locations; unresolved history is shown as “not located.”
- Claude Code active quota: optional `~/Library/Caches/codexU/claude-code/statusline-snapshot.json`; without it, 5-hour and 7-day quota show `--`.
- Update checks: default access to the GitHub Releases API for public `shanggqm/codexU` release metadata, cached in `~/Library/Caches/codexU/update-check.json`.

Current Codex quota APIs expose rolling-window percentages and reset times, not absolute account quota sizes. Claude Code support reads local history and an optional active snapshot; it is not a Claude.ai official billing view. See [RESEARCH.md](RESEARCH.md) for the data model and fallback behavior.

## FAQ

### Is codexU an official OpenAI product?

No. codexU is an unofficial local macOS utility for reading local Codex app-server responses and local `~/.codex/` data.

### Does codexU upload my Codex threads or usage data?

No. codexU reads Codex quota, local SQLite usage, and automation metadata locally. It does not upload that data to a third-party service. Update checks only request public GitHub Release metadata and do not include local usage, threads, paths, logs, or account data.

### Why does codexU show remaining percentage instead of absolute quota?

The current local Codex API exposes rolling-window usage percentages and reset times, not absolute quota sizes. codexU therefore shows remaining percentages for the 5-hour and 7-day windows.

### Does codexU support Intel Macs?

Yes. Intel Macs should use `codexU-<version>-mac-x86_64.dmg`. From source, package it with `make release-intel`, or override `TARGET_TRIPLE="x86_64-apple-macos13.0"` from a compatible toolchain.

## License

MIT. See [LICENSE](LICENSE).

## WeChat Official Account

Scan the QR code to follow my WeChat official account for AI tools, Codex usage notes, and independent product building.

<img src="docs/wechat-official-account-qr.png" alt="WeChat official account QR code" width="220" />

## User Community

Scan to join the Chinese-language codexU user community for usage tips, issue feedback, and open-source collaboration.

<img src="docs/codexu-community-qr.jpg" alt="codexU user community WeChat QR code" width="320" />
