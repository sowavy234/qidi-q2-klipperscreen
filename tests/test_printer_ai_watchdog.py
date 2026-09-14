import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE = Path(__file__).parents[1] / "tools" / "printer_ai_watchdog.py"
SPEC = importlib.util.spec_from_file_location("printer_ai_watchdog", MODULE)
WATCHDOG = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = WATCHDOG
SPEC.loader.exec_module(WATCHDOG)


def config(path):
    return {
        "moonraker_url": "http://printer",
        "poll_seconds": 10,
        "audit_log": str(path),
        "timeouts": {"http": 1},
        "thermal_limits": {"extruder": 310, "heater_bed": 125},
        "ollama": {"enabled": False, "url": "http://ollama", "model": "test",
                   "confidence_threshold": 0.9},
        "action_policy": {"enabled": True, "allow": ["pause"], "cooldown_seconds": 60},
        "authorization": {
            "require_authenticated_siri_request": True,
            "allow_direct_watchdog_actions": False,
            "require_printer_confirmation_for_actions": True,
        },
    }


class WatchdogTests(unittest.TestCase):
    def test_thermal_signal_is_deterministic(self):
        with tempfile.TemporaryDirectory() as directory:
            watcher = WATCHDOG.Watchdog(config(Path(directory) / "audit"))
            action, evidence = watcher.deterministic_thermal_action(
                {"extruder": {"temperature": 311}})
            self.assertEqual((action, evidence), ("pause", "extruder temperature 311 >= limit 310"))

    def test_unknown_model_action_is_rejected(self):
        with self.assertRaises(WATCHDOG.WatchdogError):
            WATCHDOG.strict_model_action({"action": "print_delete", "confidence": 1, "evidence": ["x"]})

    def test_malformed_endpoint_response_is_rejected(self):
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, _): return b"[]"
        with tempfile.TemporaryDirectory() as directory:
            watcher = WATCHDOG.Watchdog(config(Path(directory) / "audit"),
                                        opener=lambda *args, **kwargs: Response())
            with self.assertRaises(WATCHDOG.WatchdogError):
                watcher.request("http://printer/status")

    def test_cooldown_blocks_second_action_and_audit_redacts(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audit.jsonl"
            now = [1000]
            settings = config(path)
            watcher = WATCHDOG.Watchdog(settings, clock=lambda: now[0])
            watcher.request = lambda *args: {"result": {}}
            request = {"source": "siri", "authenticated": True,
                       "operation": "pause", "printer_confirmed": True}
            self.assertFalse(watcher.act("pause", ["temperature"]))
            self.assertTrue(watcher.act("pause", ["temperature"], request))
            self.assertFalse(watcher.act("pause", ["token=secret"]))
            records = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual(len(records), 3)
            self.assertEqual(records[1]["details"]["action"], "pause")

    def test_direct_watchdog_action_is_denied_without_siri_context(self):
        with tempfile.TemporaryDirectory() as directory:
            watcher = WATCHDOG.Watchdog(config(Path(directory) / "audit"))
            watcher.request = lambda *args: {"result": {}}
            self.assertFalse(watcher.act("pause", ["model"]))

    def test_read_only_siri_request_cannot_authorize_action(self):
        request = {"source": "siri", "authenticated": True,
                   "operation": "status", "printer_confirmed": False}
        self.assertFalse(WATCHDOG.Watchdog._valid_request(request, "pause"))

    def test_model_consultation_requires_authenticated_siri_request(self):
        with tempfile.TemporaryDirectory() as directory:
            watcher = WATCHDOG.Watchdog(config(Path(directory) / "audit"))
            with self.assertRaises(WATCHDOG.WatchdogError):
                watcher.model_action({}, None)
