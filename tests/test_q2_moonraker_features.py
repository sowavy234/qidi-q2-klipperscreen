import importlib.util
import pathlib
import sys
import unittest


MODULE_PATH = pathlib.Path(__file__).parents[1] / "tools" / "q2-moonraker-features.py"
SPEC = importlib.util.spec_from_file_location("q2_moonraker_features", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
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
                "gcode_macro SELECT_TOOL",
            ]
        )

        self.assertTrue(features["motion"])
        self.assertTrue(features["homing"])
        self.assertTrue(features["extrusion"])
        self.assertTrue(features["bed_temperature"])
        self.assertTrue(features["print_controls"])
        self.assertEqual(features["filament_macros"]["load"], True)
        self.assertEqual(features["filament_macros"]["select_tool"], True)
        self.assertEqual(features["filament_macros"]["purge"], False)

    def test_missing_objects_disable_controls(self):
        features = MODULE.detect(["toolhead"])

        self.assertFalse(features["motion"])
        self.assertFalse(features["homing"])
        self.assertFalse(features["extrusion"])
        self.assertFalse(features["temperature"])
        self.assertFalse(features["fan"])
        self.assertFalse(features["print_controls"])
        self.assertEqual(features["gcode_macros"], [])

    def test_non_heater_extruder_objects_do_not_enable_temperature(self):
        features = MODULE.detect(["toolhead", "gcode", "extruder_stepper"])

        self.assertFalse(features["temperature"])

    def test_request_rejects_non_object_json(self):
        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return b"[]"

        original = MODULE.urllib.request.urlopen
        MODULE.urllib.request.urlopen = lambda *args, **kwargs: Response()
        try:
            with self.assertRaises(ValueError):
                MODULE.request("http://printer", "printer/objects/list")
        finally:
            MODULE.urllib.request.urlopen = original


if __name__ == "__main__":
    unittest.main()
