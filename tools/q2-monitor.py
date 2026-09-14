#!/usr/bin/env python3
"""Bounded monitoring and accessible state presentation helpers."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class MonitorResult:
    state: str
    problem: str | None
    watcher: str
    offline: bool = False


STATE_STYLE = {
    "idle": ("#2d3748", "Idle / ready"),
    "heating": ("#c05621", "Heating"),
    "printing": ("#087f5b", "Printing"),
    "paused": ("#975a16", "Paused"),
    "complete": ("#2b6cb0", "Completed"),
    "error": ("#c53030", "Error"),
    "offline": ("#4a5568", "Offline"),
}


def state_style(state: str) -> dict[str, str]:
    color, label = STATE_STYLE.get(state.lower(), STATE_STYLE["error"])
    return {"color": color, "label": label, "icon_required": "true"}


def validate_monitor_payload(payload: dict[str, object]) -> MonitorResult:
    state = str(payload.get("state", "")).lower()
    if state not in STATE_STYLE:
        raise ValueError("unknown printer state")
    watcher = str(payload.get("watcher", "unavailable")).lower()
    if watcher not in {"ok", "problem", "unavailable"}:
        raise ValueError("invalid watcher state")
    problem = payload.get("problem")
    if problem is not None and not isinstance(problem, str):
        raise ValueError("problem must be text")
    return MonitorResult(state, problem, watcher, state == "offline")


def should_continue_monitoring(state: str, enabled: bool) -> bool:
    return enabled and state.lower() in {"printing", "paused", "heating"}


def deduplicate_alerts(previous: set[str], result: MonitorResult) -> list[str]:
    alerts = set()
    if result.offline:
        alerts.add("offline")
    if result.problem:
        alerts.add(result.problem)
    if result.watcher == "problem":
        alerts.add("watcher")
    return sorted(alerts - previous)
