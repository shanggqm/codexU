import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "collector", Path(__file__).resolve().parents[1] / "Resources/remote-usage-collector.py")
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)


class RemoteUsageTests(unittest.TestCase):
    def test_whitelist_never_exports_content_or_credentials(self):
        secret = "PRIVATE-PROMPT-OR-TOKEN"
        source = [
            {"type": "session_meta", "payload": {"forked_from_id": "parent", "instructions": secret}},
            {"type": "turn_context", "payload": {"model": "gpt-5.5", "developer_instructions": secret}},
            {"type": "event_msg", "payload": {"type": "thread_settings_applied", "thread_settings": {
                "service_tier": "fast", "secret": secret}}},
            {"type": "event_msg", "payload": {"type": "token_count", "rate_limits": secret, "info": {
                "total_token_usage": {"input_tokens": 100, "output_tokens": 20,
                                      "cached_input_tokens": 30, "total_tokens": 120, "secret": secret},
                "last_token_usage": {"input_tokens": 100, "output_tokens": 20, "total_tokens": 120}}}},
            {"type": "response_item", "payload": {"type": "message", "content": secret}},
            {"type": "response_item", "payload": {"type": "function_call", "arguments": secret}},
        ]
        result = [collector.event_metadata(e) for e in source]
        self.assertNotIn(secret, json.dumps(result))
        self.assertEqual(result[0]["payload"]["forked_from_id"], "parent")
        self.assertEqual(result[3]["payload"]["info"]["total_token_usage"]["cached_input_tokens"], 30)
        self.assertEqual(result[-2:], [None, None])

    def fixture(self, root):
        home = root / ".codex"
        home.mkdir()
        log = home / "session.jsonl"
        log.write_text(json.dumps({"type": "event_msg", "timestamp": "2026-09-01T12:00:00Z",
                                  "payload": {"type": "token_count", "info": {
                                      "total_token_usage": {"input_tokens": 100, "total_tokens": 100}}}}) + "\n")
        db = sqlite3.connect(home / "state_5.sqlite")
        db.execute("CREATE TABLE threads (id,tokens_used,updated_at,model,cwd,rollout_path,title)")
        db.execute("INSERT INTO threads VALUES (?,?,?,?,?,?,?)",
                   ("thread-1", 100, 1788264000, "gpt-5.5", "/project", str(log), "PRIVATE-TITLE"))
        db.commit()
        db.close()
        return home, log

    def test_real_sqlite_and_partial_active_line(self):
        with tempfile.TemporaryDirectory() as directory:
            home, log = self.fixture(Path(directory))
            with log.open("a") as stream:
                stream.write('{"type":')
            before = (home / "state_5.sqlite").read_bytes()
            result = collector.collect(home)
            self.assertNotIn("PRIVATE-TITLE", result)
            result = json.loads(result)
            self.assertEqual(result["threads"][0]["tokens"], 100)
            self.assertEqual(len(result["threads"][0]["events"]), 1)
            self.assertEqual(result["missingRollouts"], 0)
            self.assertEqual(before, (home / "state_5.sqlite").read_bytes())

    def test_outside_home_symlink_is_not_read(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home, log = self.fixture(root)
            outside = root / "private.jsonl"
            log.rename(outside)
            log.symlink_to(outside)
            result = json.loads(collector.collect(home))
            self.assertEqual(result["missingRollouts"], 1)
            self.assertEqual(result["threads"][0]["events"], [])

    def test_missing_database_and_snapshot_limit_fail_explicitly(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                collector.collect(directory)
            home, _ = self.fixture(Path(directory))
            original = collector.MAX_BYTES
            try:
                collector.MAX_BYTES = 100
                with self.assertRaises(OverflowError):
                    collector.collect(home)
            finally:
                collector.MAX_BYTES = original

    def test_invalid_counters_fail_instead_of_silently_undercounting(self):
        for value in [-1, True, 1_000_000_000_001]:
            with self.assertRaises(OverflowError):
                collector.event_metadata({"type": "event_msg", "payload": {
                    "type": "token_count", "info": {"total_token_usage": {"input_tokens": value}}}})


if __name__ == "__main__":
    unittest.main()
