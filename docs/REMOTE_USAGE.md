# Optional SSH usage sources (macOS)

codexU can include Codex usage from your own SSH development machines. This is
opt-in: without the configuration below, codexU does not start SSH or contact any
development host. No remote daemon, public endpoint, account token or third-party
service is required. Windows does not implement this feature yet.

## Setup

1. Ensure `ssh your-dev-alias python3 --version` works without a password prompt.
   Configure keys, ports and any jump host in `~/.ssh/config`, and verify the host
   key interactively before enabling collection. codexU requires an already trusted
   host key and never accepts a new or changed key automatically.
2. Create `~/.config/codexU/remote-hosts.json` on the Mac:

   ```json
   {
     "hosts": [
       {"name": "dev", "sshHost": "your-dev-alias", "codexHome": "~/.codex"}
     ]
   }
   ```

3. Refresh codexU. Diagnostics report each source's last collection time or an
   explicit unavailable/cached state. Remove the file or use `{"hosts":[]}` to
   disable collection; the next refresh returns to local-only totals.

`name` is a unique display label (letters, digits, `.`, `_`, `-`, max 40 chars).
`sshHost` is an SSH alias or `user@hostname`, not a command or URI. Use SSH config
for ports and IPv6 addresses. Up to four unique destinations are supported.
`codexHome` is optional: when omitted the remote Python process uses its
`CODEX_HOME` environment variable or `~/.codex`. An interactive shell's environment
may differ, so specify the path when using a custom installation. Each destination
must run a POSIX system with Python 3 and a readable Codex `state_5.sqlite` (or
`sqlite/state_5.sqlite`) and its session JSONL files.

## Statistics and boundaries

- Token totals, daily/model trends, project usage and API-equivalent value include
  local and configured remote records. Account quota percentages still come from
  the locally signed-in Codex account; they are never added across machines. Only
  configure accounts whose usage you intend to combine.
- Projects from remote hosts use the `ssh:<name>:` prefix. Recent remote usage
  entries show a generic host label instead of exporting private thread titles.
- Tasks, tools, skills, leadership and inference performance are not remotely
  collected. This is a usage collector, not a remote task controller.
- A copied or moved session with the same thread UUID is counted once: choose the
  largest cumulative token total, then the newest update, with local winning an
  exact tie. Existing fork-prefix deduplication also applies to the exported token
  events. Independently continuing divergent copies of the same UUID cannot be
  reliably reconciled; use distinct sessions for independent work.
- Only rollouts inside the configured Codex home are read, including archived
  rollouts referenced by the database. Missing logs are reported explicitly;
  detailed trends and pricing may cover fewer records than the thread total.
  Existing approximate fallback applies when detailed events are unavailable.
- Hosts are checked at most once every five minutes while the app refreshes. A
  failed fetch keeps the last successful snapshot for up to seven days, with its
  collection timestamp shown in diagnostics. Older/missing snapshots are excluded
  with a warning, not interpreted as zero usage. Refreshing does not bypass the
  five-minute retry interval; restart the app to retry immediately after setup.

## Privacy, limits and storage

The bundled Python collector runs over SSH stdin without installation. It opens
the remote database read-only and exports only thread IDs, model/project metadata,
timestamps, counters, service tier and fork parent IDs. It does not export account
credentials, thread titles, prompts, responses, tool calls/arguments/output, full
logs, or a copy of the database. No Mac usage is uploaded to the remote host.

Snapshots and sanitized token-event files are stored beneath
`~/Library/Caches/codexU/remote-usage/`, separate from the live `~/.codex` database.
The app builds a temporary usage-only index and removes it after aggregation.
The existing analytics caches may also contain aggregate remote statistics.
Removing a source excludes it on refresh; while sources remain enabled, inactive
source cache directories are pruned. To erase all downloaded snapshots, quit
codexU and remove the `remote-usage` cache directory. No credentials are stored there.

Each fetch is limited to 30 seconds, 32 MiB and 20,000 nonempty threads, with an
additional 25-second deadline in the remote collector. Counters above one trillion
tokens are rejected to bound aggregation arithmetic. Oversized snapshots fail
explicitly without replacing the previous snapshot. Each log line is bounded to
4 MiB; malformed/incomplete lines are ignored, as can occur during an active write.
Fetching is done on the existing background data-loading queue; unreachable hosts
can delay a refresh. SSH uses batch mode, strict host key checks, no connection
multiplexing, and no requested port forwarding. Existing user SSH configuration
(including a ProxyJump/ProxyCommand if configured) still applies.

## Development checks

```sh
make test-remote-usage
make build
build/codexU.app/Contents/MacOS/codexU --dump-json
python3 scripts/test-remote-usage-integration.py
```

Use synthetic databases and logs for tests and PR evidence. Do not attach real
remote snapshots or SSH configuration to public issues.

`--dump-json --skip-account` probes usage without starting the Codex account
app-server. The integration test uses this with an isolated home and synthetic
snapshots so that Codex does not attempt to migrate its fixture database.
