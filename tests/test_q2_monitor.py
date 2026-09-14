import importlib.util
import pathlib
import sys
import unittest

path = pathlib.Path(__file__).parents[1] / "tools" / "q2-monitor.py"
spec = importlib.util.spec_from_file_location("q2_monitor", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class MonitorTests(unittest.TestCase):
    def test_payload_and_stop_condition(self):
        result = module.validate_monitor_payload({"state": "printing", "watcher": "ok"})
        self.assertTrue(module.should_continue_monitoring(result.state, True))
        self.assertFalse(module.should_continue_monitoring("complete", True))

    def test_alerts_are_deduplicated(self):
        result = module.validate_monitor_payload(
            {"state": "paused", "watcher": "problem", "problem": "spaghetti"}
        )
        self.assertEqual(module.deduplicate_alerts(set(), result), ["spaghetti", "watcher"])
        self.assertEqual(module.deduplicate_alerts({"spaghetti", "watcher"}, result), [])

    def test_accessible_state_style_has_text_and_icon_requirement(self):
        style = module.state_style("printing")
        self.assertEqual(style["label"], "Printing")
        self.assertEqual(style["icon_required"], "true")
        self.assertEqual(module.state_style("unknown")["label"], "Error")


if __name__ == "__main__":
    unittest.main()
