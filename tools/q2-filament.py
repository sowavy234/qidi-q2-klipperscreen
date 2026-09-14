#!/usr/bin/env python3
"""Safe QIDI Q2 filament-profile and camera capability helpers."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class FilamentProfile:
    name: str
    nozzle_target: int
    bed_target: int
    requirements: str = "standard hotend"


PROFILES = {
    "abs": FilamentProfile("ABS", 260, 100),
    "asa": FilamentProfile("ASA", 260, 100),
    "pla": FilamentProfile("PLA", 220, 60),
    "petg": FilamentProfile("PETG", 245, 80),
    "tpu": FilamentProfile("TPU", 230, 50),
    "pa6-gf": FilamentProfile("PA6-GF", 270, 90, "hardened hotend, enclosure, and dryer"),
    "pa6-cf": FilamentProfile("PA6-CF", 270, 90, "hardened hotend, enclosure, and dryer"),
    "paht": FilamentProfile("PAHT", 280, 100, "hardened hotend, enclosure, and dryer"),
}


def select_profile(name: str) -> FilamentProfile:
    """Return a known profile; never turn arbitrary input into temperatures."""
    key = name.strip().lower()
    try:
        return PROFILES[key]
    except KeyError as error:
        choices = ", ".join(sorted(PROFILES))
        raise ValueError(f"unknown filament profile {name!r}; choose: {choices}") from error


def detect_camera(video_devices: Iterable[str], libmpv_available: bool) -> dict[str, object]:
    devices = sorted(str(Path(device)) for device in video_devices if str(device))
    return {
        "available": bool(devices and libmpv_available),
        "video_devices": devices,
        "libmpv": libmpv_available,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=sorted(PROFILES), help="Select a safe material profile")
    parser.add_argument("--camera-device", action="append", default=[], help="Detected /dev/video device")
    parser.add_argument("--libmpv", action="store_true", help="libmpv is installed")
    args = parser.parse_args()
    result: dict[str, object] = {"camera": detect_camera(args.camera_device, args.libmpv)}
    if args.profile:
        result["filament"] = asdict(select_profile(args.profile))
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
