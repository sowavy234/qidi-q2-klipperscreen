#!/usr/bin/env python3
"""Detect the Moonraker/Klipper objects that make QIDI controls safe to show."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from typing import Any


def request(base_url: str, path: str) -> dict[str, Any]:
    with urllib.request.urlopen(f"{base_url.rstrip('/')}/{path}", timeout=2) as response:
        payload = json.load(response)
    result = payload.get("result")
    if not isinstance(result, dict):
        raise ValueError(f"Moonraker returned no result for {path}")
    return result


def detect(objects: list[str]) -> dict[str, Any]:
    available = set(objects)
    macros = sorted(
        name.removeprefix("gcode_macro ")
        for name in available
        if name.startswith("gcode_macro ")
    )
    return {
        "motion": all(name in available for name in ("toolhead", "gcode")),
        "homing": "toolhead" in available,
        "extrusion": "extruder" in available,
        "temperature": any(name.startswith("extruder") for name in available),
        "bed_temperature": "heater_bed" in available,
        "fan": "fan" in available,
        "lights": any(
            name.startswith(("output_pin ", "gcode_macro SET_LED"))
            for name in available
        ),
        "print_controls": "print_stats" in available,
        "filament_macros": {
            action: f"{action.upper()}_FILAMENT" in macros
            for action in ("load", "unload", "purge", "select_tool")
        },
        "gcode_macros": macros,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:7125")
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args()
    try:
        result = request(args.url, "printer/objects/list")
        objects = result.get("objects")
        if not isinstance(objects, list) or not all(isinstance(item, str) for item in objects):
            raise ValueError("Moonraker returned an invalid object list")
        features = detect(objects)
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(f"feature detection failed: {error}", file=sys.stderr)
        return 1
    if args.as_json:
        print(json.dumps(features, sort_keys=True))
    else:
        for name, enabled in features.items():
            print(f"{name}: {enabled}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
