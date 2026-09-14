import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).parents[1] / "tools" / "q2-moonraker-features.py"
SPEC = importlib.util.spec_from_file_location("q2_moonraker_features", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class FeatureDetectionTests(unittest.TestCase):
    def test_detects_standard_q2_objects_and_macros(self):
        features = MODULE.detect(
            [
                "toolhead",
                "gcode",
                "extruder",
                "heater_bed",
                "fan",
                "print_stats",
                "gcode_macro LOAD_FILAMENT",
                "gcode_macro UNLOAD_FILAMENT",
            ]
        )

        self.assertTrue(features["motion"])
        self.assertTrue(features["homing"])
        self.assertTrue(features["extrusion"])
        self.assertTrue(features["bed_temperature"])
        self.assertTrue(features["print_controls"])
        self.assertEqual(features["filament_macros"]["load"], True)
        self.assertEqual(features["filament_macros"]["purge"], False)

    def test_missing_objects_disable_controls(self):
        features = MODULE.detect(["toolhead"])

        self.assertFalse(features["motion"])
        self.assertTrue(features["homing"])
        self.assertFalse(features["extrusion"])
        self.assertFalse(features["fan"])
        self.assertFalse(features["print_controls"])
        self.assertEqual(features["gcode_macros"], [])


if __name__ == "__main__":
    unittest.main()
