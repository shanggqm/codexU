#!/usr/bin/env python3
"""Probe the built macOS app with synthetic local/remote sessions only."""
import datetime
import hashlib
import json
import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "build/codexU.app/Contents/MacOS/codexU"


def run():
    with tempfile.TemporaryDirectory(prefix="codexu-remote-test-") as temporary:
        home = Path(temporary)
        codex = home / ".codex"
        codex.mkdir()
        now = datetime.datetime.now(datetime.timezone.utc)
        # Midday UTC avoids crossing a boundary between fixture creation and probe.
        today = now.replace(hour=0, minute=0, second=1, microsecond=0)
        yesterday = today - datetime.timedelta(days=1)

        def event(total, at):
            return {"type": "event_msg", "timestamp": at.isoformat(), "payload": {
                "type": "token_count", "info": {"total_token_usage": {
                    "input_tokens": total, "cached_input_tokens": 0,
                    "output_tokens": 0, "reasoning_output_tokens": 0, "total_tokens": total}}}}

        def events(total, at, parent=None):
            return [{"type": "session_meta", "timestamp": at.isoformat(),
                     "payload": {"forked_from_id": parent}},
                    {"type": "turn_context", "timestamp": at.isoformat(), "payload": {"model": "gpt-5.5"}},
                    event(total, at)]

        local_log = codex / "local.jsonl"
        local_log.write_text("\n".join(json.dumps(e, separators=(",", ":")) for e in events(100, today)) + "\n")
        db = sqlite3.connect(codex / "state_5.sqlite")
        db.execute("CREATE TABLE threads (id TEXT PRIMARY KEY,tokens_used INTEGER,updated_at REAL,"
                   "model TEXT,cwd TEXT,rollout_path TEXT,title TEXT,archived INTEGER,recency_at REAL)")
        db.execute("INSERT INTO threads VALUES (?,?,?,?,?,?,?,?,?)",
                   ("local", 100, now.timestamp(), "gpt-5.5", "/fixture", str(local_log), "Fixture", 0, now.timestamp()))
        db.commit()
        db.close()
        original = (codex / "state_5.sqlite").read_bytes()
        config = home / ".config/codexU"
        config.mkdir(parents=True)
        # .invalid is reserved and cannot resolve to a production host. A failed SSH
        # attempt exercises the cached-source path without contacting a real server.
        destination = "codexu-fixture.invalid"
        (config / "remote-hosts.json").write_text(json.dumps({"hosts": [{"name": "fixture", "sshHost": destination}]}))
        cache_root = home / "Library/Caches/codexU"
        cache = cache_root / "remote-usage" / hashlib.sha256((destination + "\n").encode()).hexdigest()
        cache.mkdir(parents=True)

        def thread(identifier, total, log_events):
            return {"id": identifier, "tokens": total, "updatedAt": now.timestamp(),
                    "model": "gpt-5.5", "cwd": "/fixture", "events": log_events}

        (cache / "snapshot.json").write_text(json.dumps({"version": 1, "collectedAt": now.timestamp(),
            "missingRollouts": 0, "threads": [
                thread("local", 100, events(100, today)),
                thread("parent", 200, events(200, yesterday)),
                thread("child", 250, events(200, yesterday, "parent") + [event(250, today)])]}))
        environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
                           CODEX_HOME=str(codex), CODEXU_HOME_OVERRIDE=str(home),
                           CODEXU_CACHE_OVERRIDE=str(cache_root), CODEXU_RUNTIME_FILTER="codex", TZ="UTC")
        result = subprocess.run([str(APP), "--dump-json", "--skip-account"], env=environment, capture_output=True)
        assert result.returncode == 0, "probe failed"
        data = json.loads(result.stdout)
        runtime = next(r for r in data["runtimes"] if r["scope"] == "codex")
        usage = runtime["snapshot"]["local"]
        if usage["lifetimeTokens"] != 350:
            print("Probe diagnostics:", runtime["snapshot"].get("messages"))
            print("Probe counts:", {k: usage.get(k) for k in ("lifetimeTokens", "todayTokens", "threadCount", "remoteSourceNames")})
            with sqlite3.connect(codex / "state_5.sqlite") as check:
                print("Fixture DB tables:", check.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall())
                print("Fixture DB rows:", check.execute("SELECT id,tokens_used FROM threads").fetchall())
            print("Fixture DB unchanged:", (codex / "state_5.sqlite").read_bytes() == original)
        assert usage["lifetimeTokens"] == 350, usage["lifetimeTokens"]
        assert usage["threadCount"] == 3
        assert usage["remoteSourceNames"] == ["fixture"]
        assert "SSH" in runtime["usageSourceLabel"]
        assert (codex / "state_5.sqlite").read_bytes() == original
        assert not list((cache_root / "remote-usage").glob("usage-*.sqlite"))
        # The two parent-prefix copies must not inflate today's detailed usage.
        detailed = usage["detailedUsage"]
        assert detailed["today"]["tokens"]["totalTokens"] == 150, detailed["today"]
        assert detailed["sevenDay"]["tokens"]["totalTokens"] == 350
        assert detailed["today"]["estimatedCostUSD"] > 0
        (config / "remote-hosts.json").unlink()
        disabled = subprocess.run([str(APP), "--dump-json", "--skip-account"], env=environment, capture_output=True)
        assert disabled.returncode == 0
        disabled_runtime = json.loads(disabled.stdout)["runtimes"][0]
        assert disabled_runtime["snapshot"]["local"]["lifetimeTokens"] == 100
        assert disabled_runtime["snapshot"]["local"]["remoteSourceNames"] == []
        assert disabled_runtime["usageSourceLabel"] == "Codex local state"
        print("Remote usage app probe passed: total=350, today=150, copied session and fork prefix deduplicated")


if __name__ == "__main__":
    run()
