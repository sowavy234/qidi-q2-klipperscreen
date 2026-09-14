#!/usr/bin/env python3
"""Compile a fail-closed Moonraker feature report into launcher settings."""
import argparse
import json
import os
import tempfile


MACRO_KEYS = ("load", "unload", "purge", "select_tool")


def compile_config(payload):
    if not isinstance(payload, dict):
        raise ValueError("feature report must be an object")
    macros = payload.get("filament_macros")
    if not isinstance(macros, dict):
        macros = {}
    values = {
        "Q2_CAPABILITIES_VALID": "1",
        "Q2_FILAMENT_LOAD": "1" if macros.get("load") is True else "0",
        "Q2_FILAMENT_UNLOAD": "1" if macros.get("unload") is True else "0",
        "Q2_FILAMENT_PURGE": "1" if macros.get("purge") is True else "0",
        "Q2_FILAMENT_SELECT_TOOL": "1" if macros.get("select_tool") is True else "0",
    }
    return "".join(f"{key}={value}\n" for key, value in values.items())


def write_atomic(path, content):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".q2-capabilities.", dir=directory, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="feature probe JSON")
    parser.add_argument("output", help="launcher environment file")
    args = parser.parse_args()
    try:
        with open(args.input, encoding="utf-8") as source:
            content = compile_config(json.load(source))
        write_atomic(args.output, content)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        # A stale capability file must never enable optional controls.
        try:
            write_atomic(args.output, "Q2_CAPABILITIES_VALID=0\n")
        except OSError:
            pass
        print(f"capability compilation failed: {error}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
