#!/usr/bin/env python3
"""Read-only SSH exporter. Stdout contains only allowlisted usage metadata."""
import json
import os
import signal
import sqlite3
import sys
import time
from pathlib import Path

MAX_BYTES = 32 * 1024 * 1024
MAX_LINE = 4 * 1024 * 1024
MAX_THREADS = 20000
COUNTERS = ("input_tokens", "cached_input_tokens", "cache_write_input_tokens",
            "output_tokens", "reasoning_output_tokens", "total_tokens")


def text(value):
    return value if isinstance(value, str) and len(value) <= 4096 else None


def event_metadata(event):
    if not isinstance(event, dict):
        return None
    payload = event.get("payload")
    if not isinstance(payload, dict):
        return None
    kind = event.get("type")
    result = None
    if kind == "session_meta":
        result = {"forked_from_id": text(payload.get("forked_from_id"))}
    elif kind == "turn_context":
        result = {"model": text(payload.get("model"))}
    elif kind == "event_msg" and payload.get("type") == "thread_settings_applied":
        settings = payload.get("thread_settings")
        if isinstance(settings, dict):
            result = {"type": "thread_settings_applied", "thread_settings": {
                "service_tier": text(settings.get("service_tier"))}}
    elif kind == "event_msg" and payload.get("type") == "token_count":
        info = payload.get("info")
        if isinstance(info, dict):
            counts = {}
            for key in ("total_token_usage", "last_token_usage"):
                usage = info.get(key)
                if isinstance(usage, dict):
                    counts[key] = {}
                    for k in COUNTERS:
                        if k in usage:
                            value = usage[k]
                            if type(value) is not int or not 0 <= value <= 1_000_000_000_000:
                                raise OverflowError("invalid token counter")
                            counts[key][k] = value
            if counts:
                result = {"type": "token_count", "info": counts}
    if result is None:
        return None
    return {"type": kind, "timestamp": text(event.get("timestamp")), "payload": result}


def collect(home):
    home = Path(home).expanduser().resolve()
    db = next((p for p in (home / "state_5.sqlite", home / "sqlite/state_5.sqlite")
               if p.is_file()), None)
    if db is None:
        raise ValueError("missing database")
    connection = sqlite3.connect(db.as_uri() + "?mode=ro", uri=True, timeout=2)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(
            "SELECT id,tokens_used,updated_at,model,cwd,rollout_path FROM threads "
            "WHERE tokens_used > 0 ORDER BY id LIMIT ?", (MAX_THREADS + 1,)).fetchall()
    finally:
        connection.close()
    if len(rows) > MAX_THREADS:
        raise ValueError("too many threads")
    threads = []
    size = 0
    missing = 0
    for row in rows:
        events = []
        path = Path(row["rollout_path"] or "")
        try:
            path = path.resolve()
            # Never follow database paths outside this explicitly configured Codex home.
            if home not in path.parents or path.suffix != ".jsonl":
                raise ValueError("invalid rollout path")
            with path.open("rb") as stream:
                while True:
                    line = stream.readline(MAX_LINE + 1)
                    if not line:
                        break
                    if len(line) > MAX_LINE:
                        while line and not line.endswith(b"\n"):
                            line = stream.readline(MAX_LINE + 1)
                        continue
                    # A running session may end with an incomplete JSON record.
                    try:
                        event = event_metadata(json.loads(line))
                    except (ValueError, UnicodeError):
                        continue
                    if event is not None:
                        size += len(json.dumps(event, separators=(",", ":")).encode()) + 1
                        if size > MAX_BYTES - 1024 * 1024:
                            raise OverflowError("snapshot too large")
                        events.append(event)
        except (OSError, ValueError):
            missing += 1
        thread = {"id": text(row["id"]), "tokens": max(0, row["tokens_used"] or 0),
                  "updatedAt": row["updated_at"] or 0, "model": text(row["model"]),
                  "cwd": text(row["cwd"]) or "", "events": events}
        if not thread["id"]:
            raise ValueError("invalid thread id")
        threads.append(thread)
    result = json.dumps({"version": 1, "collectedAt": time.time(),
                         "missingRollouts": missing, "threads": threads}, separators=(",", ":"))
    if len(result.encode()) > MAX_BYTES:
        raise OverflowError("snapshot too large")
    return result


def main():
    # Also bound the remote process if the SSH client disconnects.
    signal.signal(signal.SIGALRM, lambda *_: sys.exit(2))
    signal.alarm(25)
    try:
        print(collect(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("CODEX_HOME", "~/.codex")))
    except Exception:
        # Raw exceptions can contain paths or transcript fragments.
        print("Remote usage collection failed (database, permissions or size limit).", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
