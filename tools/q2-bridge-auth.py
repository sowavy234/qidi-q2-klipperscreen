#!/usr/bin/env python3
"""In-memory pairing and challenge gates for a locked-down QIDI bridge."""

from __future__ import annotations

import hashlib
import hmac
import secrets
import time
from dataclasses import dataclass


READ_ONLY_ACTIONS = {"status", "check"}
SENSITIVE_ACTIONS = {
    "motion", "heating", "purge", "smart_level", "pause", "cancel",
    "firmware_restart",
}


@dataclass
class Pairing:
    printer_id: str
    code_hash: str
    expires_at: float
    paired: bool = False


class BridgeAuthorizer:
    def __init__(self, printer_id: str, clock=time.time):
        if not printer_id or len(printer_id) > 128:
            raise ValueError("printer identity is required")
        self.printer_id = printer_id
        self._clock = clock
        self._pairing: Pairing | None = None
        self._challenge_hash: str | None = None
        self._challenge_expires = 0.0
        self._challenge_used = False
        self._failures = 0

    @staticmethod
    def _hash(value: str) -> str:
        return hashlib.sha256(value.encode("utf-8")).hexdigest()

    def begin_pairing(self, ttl: int = 300) -> str:
        code = f"{secrets.randbelow(1_000_000):06d}"
        self._pairing = Pairing(self.printer_id, self._hash(code), self._clock() + ttl)
        return code

    def pair(self, printer_id: str, code: str) -> bool:
        pairing = self._pairing
        if self._failures >= 5:
            return False
        if not pairing or pairing.paired or pairing.expires_at <= self._clock():
            return False
        valid = (
            hmac.compare_digest(pairing.printer_id, printer_id)
            and hmac.compare_digest(pairing.code_hash, self._hash(code))
        )
        if valid:
            pairing.paired = True
            self._failures = 0
        else:
            self._failures += 1
        return valid

    def issue_challenge(self, ttl: int = 60) -> str:
        if not self._pairing or not self._pairing.paired:
            raise PermissionError("printer is not paired")
        code = f"{secrets.randbelow(1_000_000):06d}"
        self._challenge_hash = self._hash(code)
        self._challenge_expires = self._clock() + ttl
        self._challenge_used = False
        return code

    def authorize(
        self,
        printer_id: str,
        action: str,
        challenge: str | None = None,
        printer_confirmed: bool = False,
    ) -> bool:
        if not self._pairing or not self._pairing.paired:
            return False
        if printer_id != self.printer_id:
            return False
        if action not in READ_ONLY_ACTIONS and action not in SENSITIVE_ACTIONS:
            return False
        if action in SENSITIVE_ACTIONS:
            if (
                not challenge
                or not printer_confirmed
                or self._challenge_used
                or self._challenge_expires <= self._clock()
                or not self._challenge_hash
                or not hmac.compare_digest(self._challenge_hash, self._hash(challenge))
            ):
                return False
            self._challenge_used = True
        return True

    def revoke(self) -> None:
        self._pairing = None
        self._challenge_hash = None
        self._challenge_expires = 0.0

    def ui_state(self) -> str:
        if not self._pairing:
            return "locked/unpaired"
        if not self._pairing.paired:
            return "pending-confirmation"
        if self._challenge_expires > self._clock() and not self._challenge_used:
            return "paired/challenge-pending"
        return "paired"
