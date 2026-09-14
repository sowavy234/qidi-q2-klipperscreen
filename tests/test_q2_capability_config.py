import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE = Path(__file__).parents[1] / "tools" / "q2-capability-config.py"
SPEC = importlib.util.spec_from_file_location("q2_capability_config", MODULE)
CAPABILITIES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CAPABILITIES)


class CapabilityConfigTests(unittest.TestCase):
    def test_exact_supported_macros_are_enabled(self):
        content = CAPABILITIES.compile_config({
            "filament_macros": {
                "load": True, "unload": False, "purge": True,
                "select_tool": True,
            }
        })
        self.assertIn("Q2_FILAMENT_LOAD=1\n", content)
        self.assertIn("Q2_FILAMENT_PURGE=1\n", content)
        self.assertIn("Q2_FILAMENT_UNLOAD=0\n", content)
        self.assertIn("Q2_FILAMENT_SELECT_TOOL=1\n", content)

    def test_missing_or_malformed_capabilities_fail_closed(self):
        content = CAPABILITIES.compile_config({"filament_macros": {}})
        self.assertNotIn("=1\n", content.replace("Q2_CAPABILITIES_VALID=1\n", ""))
        with self.assertRaises(ValueError):
            CAPABILITIES.compile_config(json.loads("[]"))

    def test_write_is_atomic_and_private(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "capabilities.env"
            CAPABILITIES.write_atomic(str(target), "Q2_CAPABILITIES_VALID=1\n")
            self.assertEqual(target.read_text(), "Q2_CAPABILITIES_VALID=1\n")
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
