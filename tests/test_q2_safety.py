import importlib.util
import pathlib
import sys
import unittest


path = pathlib.Path(__file__).parents[1] / "tools" / "q2-safety.py"
spec = importlib.util.spec_from_file_location("q2_safety", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class SafetyTests(unittest.TestCase):
    def test_engineering_profiles_are_conservative_and_require_hardware(self):
        profile = module.select_profile("PA6-CF")
        self.assertEqual((profile.nozzle_target, profile.bed_target), (270, 90))
        self.assertIn("hardened", profile.requirements)

    def test_macro_requires_detection_confirmation_and_homing(self):
        with self.assertRaises(PermissionError):
            module.confirmed_macro_command("KAMP_PURGE", {"KAMP_PURGE"}, confirmed=False, homed=True)
        with self.assertRaises(PermissionError):
            module.confirmed_macro_command("KAMP_PURGE", {"KAMP_PURGE"}, confirmed=True, homed=False)
        self.assertEqual(
            module.confirmed_macro_command("KAMP_PURGE", {"KAMP_PURGE"}, confirmed=True, homed=True),
            "KAMP_PURGE",
        )

    def test_collision_bounds_reject_corner_crash(self):
        with self.assertRaises(ValueError):
            module.validate_bounds(250, 10, 1, (0, 220, 0, 220, 0, 250))

    def test_watcher_requires_executable_and_authenticated_endpoint(self):
        unavailable = module.watcher_capability("/missing", "http://printer.local/hook", None)
        self.assertFalse(unavailable["available"])
        local = module.watcher_capability(str(path), "http://127.0.0.1:8123/hook", "token")
        self.assertTrue(local["alert_endpoint"])

    def test_smart_purge_is_disabled_without_geometry_and_protects_rear_corners(self):
        limits = (0, 220, 0, 220, 0, 250)
        self.assertFalse(module.smart_purge_dry_run(None, limits)["available"])
        geometry = module.ChuteGeometry(110, 215, 10, 5, 200, 15)
        with self.assertRaises(PermissionError):
            module.validate_purge_position(
                geometry, limits, homed=True, current_z=10, confirmed=False, soft_limits=True
            )
        self.assertEqual(
            module.validate_purge_position(
                geometry, limits, homed=True, current_z=10, confirmed=True, soft_limits=True
            ),
            "PURGE_FILAMENT X=110 Y=215 Z=10",
        )
        corner = module.ChuteGeometry(5, 215, 10, 5, 200, 15)
        with self.assertRaises(ValueError):
            module.validate_purge_position(
                corner, limits, homed=True, current_z=10, confirmed=True, soft_limits=True
            )


if __name__ == "__main__":
    unittest.main()
