#!/usr/bin/env python3
"""Validation helpers for opt-in QIDI Q2 motion, heat, and watcher hooks."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse


@dataclass(frozen=True)
class FilamentProfile:
    name: str
    nozzle_target: int
    bed_target: int
    requirements: str


PROFILES = {
    "pla": FilamentProfile("PLA", 220, 60, "standard hotend"),
    "petg": FilamentProfile("PETG", 245, 80, "standard hotend"),
    "abs": FilamentProfile("ABS", 260, 100, "enclosure recommended"),
    "asa": FilamentProfile("ASA", 260, 100, "enclosure recommended"),
    "tpu": FilamentProfile("TPU", 230, 50, "slow extrusion and dry filament"),
    "pa6-gf": FilamentProfile("PA6-GF", 270, 90, "hardened hotend, enclosure, and dryer"),
    "pa6-cf": FilamentProfile("PA6-CF", 270, 90, "hardened hotend, enclosure, and dryer"),
    "paht": FilamentProfile("PAHT", 280, 100, "hardened hotend, enclosure, and dryer"),
}

ADVANCED_MACROS = {
    "PURGE_FILAMENT",
    "SMART_PARK",
    "KAMP_PURGE",
    "Z_TILT_ADJUST",
    "SCREWS_TILT_CALCULATE",
    "BED_MESH_CALIBRATE",
    "BED_MESH_PROFILE",
    "SET_FAN_SPEED",
    "PAUSE",
}


@dataclass(frozen=True)
class ChuteGeometry:
    x: float
    y: float
    park_z: float
    clearance_z: float
    rear_y: float
    corner_margin: float


def select_profile(name: str) -> FilamentProfile:
    try:
        return PROFILES[name.strip().lower()]
    except KeyError as error:
        raise ValueError(f"unsupported filament profile: {name!r}") from error


def validate_bounds(x: float, y: float, z: float, limits: tuple[float, float, float, float, float, float]) -> tuple[float, float, float]:
    xmin, xmax, ymin, ymax, zmin, zmax = limits
    values = (x, y, z)
    for value, low, high in zip(values, (xmin, ymin, zmin), (xmax, ymax, zmax)):
        if not low <= value <= high:
            raise ValueError(f"coordinate {value} is outside configured soft limits")
    return values


def validate_purge_position(
    geometry: ChuteGeometry | None,
    limits: tuple[float, float, float, float, float, float],
    *,
    homed: bool,
    current_z: float,
    confirmed: bool,
    soft_limits: bool,
) -> str:
    """Validate a configured rear-chute position without inventing coordinates."""
    if geometry is None:
        raise ValueError("rear waste-chute geometry is not configured")
    if not homed:
        raise PermissionError("printer must be homed before smart purge")
    if not confirmed:
        raise PermissionError("explicit confirmation is required before smart purge")
    if not soft_limits:
        raise PermissionError("soft limits must be enabled before smart purge")
    xmin, xmax, ymin, ymax, zmin, zmax = limits
    validate_bounds(geometry.x, geometry.y, geometry.park_z, limits)
    if geometry.y < geometry.rear_y:
        raise ValueError("purge position is not in the configured rear zone")
    if geometry.park_z < geometry.clearance_z or current_z < geometry.clearance_z:
        raise ValueError("smart purge requires configured safe Z clearance")
    if (
        geometry.x < xmin + geometry.corner_margin
        or geometry.x > xmax - geometry.corner_margin
    ):
        raise ValueError("purge position is inside a protected corner margin")
    return (
        f"PURGE_FILAMENT X={geometry.x:g} Y={geometry.y:g} "
        f"Z={geometry.park_z:g}"
    )


def smart_purge_dry_run(
    geometry: ChuteGeometry | None,
    limits: tuple[float, float, float, float, float, float],
) -> dict[str, object]:
    try:
        command = validate_purge_position(
            geometry,
            limits,
            homed=True,
            current_z=geometry.clearance_z if geometry else 0,
            confirmed=True,
            soft_limits=True,
        )
    except (PermissionError, ValueError) as error:
        return {"available": False, "reason": str(error)}
    return {"available": True, "command": command}


def confirmed_macro_command(
    macro: str,
    available_macros: set[str],
    *,
    confirmed: bool,
    homed: bool,
) -> str:
    name = macro.strip().upper()
    if name not in available_macros:
        raise ValueError(f"macro is not detected: {name}")
    if not confirmed:
        raise PermissionError("explicit confirmation is required before running a macro")
    if name not in {"PAUSE"} and not homed:
        raise PermissionError("printer must be homed before running motion or heat macros")
    return name


def watcher_capability(command: str | None, webhook_url: str | None, token: str | None) -> dict[str, object]:
    executable = bool(command and Path(command).is_file())
    parsed = urlparse(webhook_url or "")
    secure_endpoint = parsed.scheme == "https" and bool(parsed.netloc)
    local_endpoint = parsed.hostname in {"127.0.0.1", "localhost"} and bool(parsed.netloc)
    configured = executable and bool(token) and (secure_endpoint or local_endpoint)
    return {"available": configured, "executable": executable, "alert_endpoint": configured}
