#!/usr/bin/env python3
"""Offline-safe validation for QIDI Q2 advanced operations."""

from __future__ import annotations

import json
import re
import tarfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse


def backup_name(now: datetime | None = None) -> str:
    stamp = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    return f"qidi-q2-config-{stamp:%Y%m%dT%H%M%SZ}.tar.gz"


def restore_path(root: Path, name: str) -> Path:
    if not re.fullmatch(r"qidi-q2-config-\d{8}T\d{6}Z\.tar\.gz", name):
        raise ValueError("invalid backup name")
    path = (root / name).resolve()
    if path.parent != root.resolve():
        raise ValueError("backup must remain inside the backup directory")
    if not path.is_file():
        raise FileNotFoundError(path)
    return path


def create_backup(source: Path, backup_dir: Path, now: datetime | None = None, keep: int = 5) -> Path:
    """Create a new archive without overwriting an existing backup."""
    if not source.is_dir() or keep < 1:
        raise ValueError("source directory and positive retention are required")
    backup_dir.mkdir(parents=True, exist_ok=True)
    destination = backup_dir / backup_name(now)
    if destination.exists():
        raise FileExistsError(destination)
    with tarfile.open(destination, "x:gz") as archive:
        archive.add(source, arcname=source.name)
    backups = sorted(backup_dir.glob("qidi-q2-config-*.tar.gz"), reverse=True)
    for old in backups[keep:]:
        old.unlink()
    return destination


def speed_value(value: float, safe_min: float, safe_max: float) -> float:
    if safe_min <= 0 or safe_min > safe_max or not safe_min <= value <= safe_max:
        raise ValueError("speed is outside configured safe bounds")
    return round(float(value), 3)


def mesh_health(points: list[list[float]], tolerance: float) -> dict[str, object]:
    if not points or any(not row for row in points) or len({len(row) for row in points}) != 1:
        return {"status": "unknown", "reason": "mesh is missing or malformed"}
    if tolerance < 0:
        raise ValueError("mesh tolerance must be non-negative")
    flat = [point for row in points for point in row]
    spread = max(flat) - min(flat)
    return {"status": "good" if spread <= tolerance else "bad", "spread": round(spread, 4)}


def smart_level_gate(macros: set[str], objects: set[str], confirmed: bool) -> dict[str, object]:
    required = {"Z_TILT_ADJUST", "BED_MESH_CALIBRATE"}
    missing = sorted(required - {name.upper() for name in macros})
    if "toolhead" not in objects:
        missing.append("toolhead")
    if missing:
        return {"available": False, "reason": "missing: " + ", ".join(missing)}
    if not confirmed:
        return {"available": False, "reason": "explicit confirmation is required"}
    return {"available": True, "macros": sorted(required)}


def watcher_alert_payload(
    watcher: str | None, webhook_url: str | None, token: str | None, event: str
) -> dict[str, object]:
    parsed = urlparse(webhook_url or "")
    if not watcher or not token or parsed.scheme not in {"https"} or not parsed.netloc:
        raise ValueError("watcher and authenticated HTTPS alert endpoint are required")
    if event not in {"spaghetti", "misprint"}:
        raise ValueError("unsupported watcher event")
    return {"event": event, "pause": True, "watcher": watcher, "authenticated": True}


def validate_mesh_json(payload: str, tolerance: float) -> dict[str, object]:
    try:
        decoded = json.loads(payload)
        points = decoded["mesh_matrix"]
    except (ValueError, KeyError, TypeError):
        return {"status": "unknown", "reason": "invalid mesh response"}
    return mesh_health(points, tolerance)


def serialize_mesh(points: list[list[float]]) -> str:
    """Serialize every mesh point for a UI tile or audit log."""
    if not points or any(not isinstance(row, list) for row in points):
        raise ValueError("mesh must contain rows of points")
    return json.dumps({"rows": len(points), "columns": len(points[0]), "points": points}, separators=(",", ":"))
