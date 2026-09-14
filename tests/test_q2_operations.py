import importlib.util
import pathlib
import sys
import unittest
import tempfile
from datetime import datetime, timezone


path = pathlib.Path(__file__).parents[1] / "tools" / "q2-operations.py"
spec = importlib.util.spec_from_file_location("q2_operations", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class OperationsTests(unittest.TestCase):
    def test_backup_name_and_restore_validation(self):
        stamp = datetime(2026, 9, 14, tzinfo=timezone.utc)
        self.assertEqual(module.backup_name(stamp), "qidi-q2-config-20260914T000000Z.tar.gz")
        with self.assertRaises(ValueError):
            module.restore_path(pathlib.Path("/tmp"), "config.tar.gz")
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "printer_data"
            source.mkdir()
            (source / "moonraker.conf").write_text("safe\n")
            archive = module.create_backup(
                source, root / "backups", datetime(2026, 9, 14, tzinfo=timezone.utc)
            )
            self.assertEqual(module.restore_path(root / "backups", archive.name), archive.resolve())

    def test_speed_bounds(self):
        self.assertEqual(module.speed_value(80, 25, 100), 80.0)
        with self.assertRaises(ValueError):
            module.speed_value(120, 25, 100)

    def test_mesh_health_and_stale_payload(self):
        self.assertEqual(module.mesh_health([[0, 0.02], [0.01, 0]], 0.05)["status"], "good")
        self.assertEqual(module.mesh_health([[0, 0.2], [0.01, 0]], 0.05)["status"], "bad")
        self.assertEqual(module.validate_mesh_json("{}", 0.05)["status"], "unknown")
        self.assertIn('"points":[[0,0.02]', module.serialize_mesh([[0, 0.02], [0.01, 0]]))

    def test_smart_level_requires_native_hooks_and_confirmation(self):
        args = ({"Z_TILT_ADJUST", "BED_MESH_CALIBRATE"}, {"toolhead"})
        self.assertFalse(module.smart_level_gate(*args, False)["available"])
        self.assertTrue(module.smart_level_gate(*args, True)["available"])
        self.assertFalse(module.smart_level_gate({"BED_MESH_CALIBRATE"}, {"toolhead"}, True)["available"])

    def test_watcher_payload_requires_authenticated_https(self):
        payload = module.watcher_alert_payload("watcher", "https://ha.example/hook", "token", "spaghetti")
        self.assertTrue(payload["pause"])
        with self.assertRaises(ValueError):
            module.watcher_alert_payload("watcher", "http://ha.example/hook", "token", "spaghetti")


if __name__ == "__main__":
    unittest.main()
