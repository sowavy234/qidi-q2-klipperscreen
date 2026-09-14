import importlib.util
import pathlib
import sys
import unittest


MODULE_PATH = pathlib.Path(__file__).parents[1] / "tools" / "q2-filament.py"
SPEC = importlib.util.spec_from_file_location("q2_filament", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class FilamentProfileTests(unittest.TestCase):
    def test_profile_maps_to_conservative_targets(self):
        self.assertEqual(MODULE.select_profile(" PETG "), MODULE.FilamentProfile("PETG", 245, 80))
        self.assertEqual(MODULE.select_profile("pla").nozzle_target, 220)

    def test_unknown_profile_is_rejected(self):
        with self.assertRaises(ValueError):
            MODULE.select_profile("mystery")

    def test_camera_requires_device_and_libmpv(self):
        self.assertTrue(MODULE.detect_camera(["/dev/video0"], True)["available"])
        self.assertFalse(MODULE.detect_camera([], True)["available"])
        self.assertFalse(MODULE.detect_camera(["/dev/video0"], False)["available"])


if __name__ == "__main__":
    unittest.main()
