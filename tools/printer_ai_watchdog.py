#!/usr/bin/env python3
"""Observe a printer with deterministic safety gates and request-gated AI advice."""
from __future__ import annotations

import argparse
import json
import os
import re
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path


ALLOWED_ACTIONS = {"none", "pause", "firmware_restart"}
READ_ONLY_OPERATIONS = {"status", "check"}
ACTION_OPERATIONS = {"pause", "firmware_restart"}
SECRET_KEYS = re.compile(r"(token|secret|password|api[_-]?key|authorization)", re.I)


class WatchdogError(Exception):
    pass


def redact(value):
    if isinstance(value, dict):
        return {k: "[REDACTED]" if SECRET_KEYS.search(k) else redact(v) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def audit(path: str, event: str, details: dict):
    record = {"ts": time.time(), "event": event, "details": redact(details)}
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, sort_keys=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def strict_model_action(payload):
    if not isinstance(payload, dict) or set(payload) != {"action", "confidence", "evidence"}:
        raise WatchdogError("model response must contain exactly action, confidence, evidence")
    action = payload["action"]
    confidence = payload["confidence"]
    evidence = payload["evidence"]
    if action not in ALLOWED_ACTIONS or not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1:
        raise WatchdogError("invalid model action or confidence")
    if not isinstance(evidence, list) or not evidence or not all(isinstance(item, str) for item in evidence):
        raise WatchdogError("evidence must be a non-empty string list")
    return payload


@dataclass
class Watchdog:
    config: dict
    opener: object = urllib.request.urlopen
    clock: object = time.time
    last_action: float = 0

    def request(self, url, body=None):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        try:
            with self.opener(request, timeout=float(self.config["timeouts"]["http"])) as response:
                result = json.loads(response.read(256 * 1024))
        except (OSError, ValueError, urllib.error.URLError) as error:
            raise WatchdogError(f"request failed: {error}") from error
        if not isinstance(result, dict):
            raise WatchdogError("endpoint returned a non-object JSON response")
        return result

    def moonraker_status(self):
        result = self.request(self.config["moonraker_url"].rstrip("/") + "/printer/objects/query?"
                              "print_stats&heater_bed&extruder&temperature_sensor mcu_temp")
        if not isinstance(result.get("result"), dict):
            raise WatchdogError("Moonraker status has no object result")
        return result["result"].get("status", {})

    def deterministic_thermal_action(self, status):
        limits = self.config["thermal_limits"]
        for name in ("extruder", "heater_bed"):
            item = status.get(name)
            if not isinstance(item, dict):
                continue
            temperature = item.get("temperature")
            maximum = limits.get(name)
            if isinstance(temperature, (int, float)) and isinstance(maximum, (int, float)) and temperature >= maximum:
                return "pause", f"{name} temperature {temperature} >= limit {maximum}"
        return "none", ""

    def can_act(self, action):
        policy = self.config["action_policy"]
        if not policy.get("enabled", False) or action not in ALLOWED_ACTIONS - {"none"}:
            return False
        if action not in policy.get("allow", []):
            return False
        if self.clock() - self.last_action < float(policy["cooldown_seconds"]):
            return False
        return True

    @staticmethod
    def _valid_request(request, action=None):
        if not isinstance(request, dict) or request.get("source") != "siri":
            return False
        if request.get("authenticated") is not True:
            return False
        operation = request.get("operation")
        if operation not in READ_ONLY_OPERATIONS | ACTION_OPERATIONS:
            return False
        if action is None:
            return True
        if operation != action:
            return False
        return request.get("printer_confirmed") is True

    def act(self, action, evidence, request=None):
        authorization = self.config.get("authorization", {})
        if (
            authorization.get("require_authenticated_siri_request") is not True
            or authorization.get("allow_direct_watchdog_actions") is not False
            or authorization.get("require_printer_confirmation_for_actions") is not True
            or not self._valid_request(request, action)
        ):
            audit(self.config["audit_log"], "action_blocked",
                  {"action": action, "evidence": evidence, "reason": "missing_authenticated_siri_request"})
            return False
        if not self.can_act(action):
            audit(self.config["audit_log"], "action_blocked", {"action": action, "evidence": evidence})
            return False
        endpoint = "/printer/print/pause" if action == "pause" else "/printer/firmware_restart"
        self.request(self.config["moonraker_url"].rstrip("/") + endpoint, {})
        self.last_action = self.clock()
        audit(self.config["audit_log"], "action_executed", {"action": action, "evidence": evidence})
        return True

    def cycle(self, request=None):
        status = self.moonraker_status()
        action, evidence = self.deterministic_thermal_action(status)
        if action != "none":
            audit(self.config["audit_log"], "safety_observation",
                  {"action": action, "evidence": evidence,
                   "reason": "watchdog_actions_require_siri_request"})
            return
        if request is None:
            audit(self.config["audit_log"], "ai_blocked",
                  {"reason": "no_authenticated_siri_request"})
            return
        authorization = self.config.get("authorization", {})
        if (
            authorization.get("require_authenticated_siri_request") is not True
            or not self._valid_request(request)
        ):
            audit(self.config["audit_log"], "ai_blocked",
                  {"reason": "invalid_authenticated_siri_request"})
            return
        if self.config["ollama"].get("enabled", False):
            action, evidence = self.model_action(status, request)
            if action != "none":
                self.act(action, evidence, request)

    def model_action(self, status, request):
        authorization = self.config.get("authorization", {})
        if (
            authorization.get("require_authenticated_siri_request") is not True
            or not self._valid_request(request)
        ):
            raise WatchdogError("AI consultation requires an authenticated Siri request")
        prompt = {"status": redact(status), "schema": {"action": "none|pause|firmware_restart",
                 "confidence": "0..1", "evidence": ["string"]},
                  "requested_operation": request["operation"],
                  "instruction": "provide bounded advice; never choose an action other than the requested operation"}
        result = self.request(self.config["ollama"]["url"].rstrip("/") + "/api/generate",
                              {"model": self.config["ollama"]["model"], "prompt": json.dumps(prompt),
                               "stream": False, "format": "json"})
        try:
            response = json.loads(result["response"])
            action = strict_model_action(response)
        except (KeyError, TypeError, ValueError, WatchdogError) as error:
            audit(self.config["audit_log"], "model_rejected", {"error": str(error)})
            return "none", []
        threshold = float(self.config["ollama"]["confidence_threshold"])
        if action["confidence"] < threshold:
            return "none", []
        if action["action"] != "none" and action["action"] != request["operation"]:
            audit(self.config["audit_log"], "model_rejected",
                  {"error": "model action does not match Siri operation"})
            return "none", []
        if request["operation"] in READ_ONLY_OPERATIONS and action["action"] != "none":
            audit(self.config["audit_log"], "model_rejected",
                  {"error": "read-only Siri operation cannot authorize printer action"})
            return "none", []
        return action["action"], action["evidence"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    args = parser.parse_args()
    with open(args.config, encoding="utf-8") as stream:
        config = json.load(stream)
    watcher = Watchdog(config)
    while True:
        try:
            watcher.cycle()
        except WatchdogError as error:
            audit(config["audit_log"], "cycle_error", {"error": str(error)})
        time.sleep(float(config["poll_seconds"]))


if __name__ == "__main__":
    main()
