import json
import pathlib
import unittest


class AppleShortcutTests(unittest.TestCase):
    def test_artifact_is_secret_free_and_matches_bridge_actions(self):
        path = pathlib.Path(__file__).parents[1] / "docs" / "apple-shortcut-qidi-q2.json"
        artifact = json.loads(path.read_text())
        self.assertTrue(artifact["security"]["never_commit_real_secrets"])
        self.assertIn("YOUR_", artifact["security"]["endpoint"])
        actions = {item.get("operation") for item in artifact["actions"]}
        self.assertTrue({"status", "check", "pause", "firmware_restart"} <= actions)
        for item in artifact["actions"]:
            if item.get("operation") in {"pause", "firmware_restart"}:
                self.assertTrue(item["requires_printer_confirmation"])
                self.assertTrue(item["requires_printer_challenge"])
