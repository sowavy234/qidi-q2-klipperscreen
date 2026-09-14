import importlib.util
import pathlib
import sys
import unittest

path = pathlib.Path(__file__).parents[1] / "tools" / "q2-bridge-auth.py"
spec = importlib.util.spec_from_file_location("q2_bridge_auth", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class AuthTests(unittest.TestCase):
    def test_pairing_identity_and_sensitive_challenge_are_required(self):
        now = [100.0]
        auth = module.BridgeAuthorizer("q2-abc", lambda: now[0])
        code = auth.begin_pairing()
        self.assertEqual(auth.ui_state(), "pending-confirmation")
        self.assertTrue(auth.pair("q2-abc", code))
        self.assertFalse(auth.authorize("q2-abc", "purge"))
        challenge = auth.issue_challenge()
        self.assertTrue(auth.authorize("q2-abc", "purge", challenge, True))
        self.assertFalse(auth.authorize("q2-abc", "purge", challenge))

    def test_expiry_replay_and_printer_mismatch_are_rejected(self):
        now = [0.0]
        auth = module.BridgeAuthorizer("q2-abc", lambda: now[0])
        code = auth.begin_pairing(ttl=5)
        now[0] = 6
        self.assertFalse(auth.pair("q2-abc", code))
        code = auth.begin_pairing()
        self.assertTrue(auth.pair("q2-abc", code))
        challenge = auth.issue_challenge(ttl=2)
        self.assertFalse(auth.authorize("other", "pause", challenge, True))
        now[0] = 9
        self.assertFalse(auth.authorize("q2-abc", "pause", challenge, True))

    def test_status_is_read_only_after_pairing_and_revoke_locks(self):
        auth = module.BridgeAuthorizer("q2-abc")
        code = auth.begin_pairing()
        self.assertTrue(auth.pair("q2-abc", code))
        self.assertTrue(auth.authorize("q2-abc", "status"))
        self.assertFalse(auth.authorize("q2-abc", "unknown"))
        auth.revoke()
        self.assertFalse(auth.authorize("q2-abc", "status"))
        self.assertEqual(auth.ui_state(), "locked/unpaired")

    def test_pairing_failures_are_rate_limited(self):
        auth = module.BridgeAuthorizer("q2-abc")
        code = auth.begin_pairing()
        for _ in range(5):
            self.assertFalse(auth.pair("q2-abc", "000000"))
        self.assertFalse(auth.pair("q2-abc", code))

    def test_pairing_code_is_single_use(self):
        auth = module.BridgeAuthorizer("q2-abc")
        code = auth.begin_pairing()
        self.assertTrue(auth.pair("q2-abc", code))
        self.assertFalse(auth.pair("q2-abc", code))


if __name__ == "__main__":
    unittest.main()
