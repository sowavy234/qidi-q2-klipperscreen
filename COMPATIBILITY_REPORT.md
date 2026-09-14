# QIDI Q2 compatibility report

## Assessment

**Partial, verified for the reference image:** QIDI Q2, `qd-q2-system
01.01.02.03`, Debian 11 ARM64, Rockchip RK3308B-S, 480×272 Goodix panel,
KlipperScreen commit `ed40799f92f8a5044082aee75b832a9e97084c7f`.

This release uses upstream KlipperScreen panels and Moonraker objects. It does
not assume proprietary QIDI macros or claim support for firmware versions that
have not been checked.

## Control compatibility

| Control group | Detection requirement | Safe behavior |
|---|---|---|
| X/Y/Z jog and homing | `toolhead`, `gcode` | Use native movement panel and configured conservative steps |
| Extrude/retract/purge | `extruder` plus a heated extruder | Native extrusion controls remain unavailable until Klipper reports the object |
| Load/unload/material selection | matching `gcode_macro LOAD_FILAMENT`, `UNLOAD_FILAMENT`, or `SELECT_TOOL` | Macro buttons are optional; missing macros are hidden |
| Pause/resume/cancel | `print_stats` | Native print controls are shown only when available |
| Fan, bed, chamber, lights | corresponding Moonraker/Klipper objects | Missing objects are hidden rather than guessed |

Run `python3 tools/q2-moonraker-features.py --json` on the printer to record
the actual object set before enabling optional macros.

Advanced hooks are templates only: rear-chute purge, KAMP purge, Smart Park,
triple-Z/screw tilt, bed mesh, fan, and watcher/webhook actions require local
configuration and explicit confirmation. No chute coordinates are assumed.
Smart Purge additionally requires measured soft limits, a homed state, safe Z
clearance, a rear-zone check, and corner margins. PA6-GF, PA6-CF, and PAHT
profiles are conservative informational targets and require a hardened
hotend, enclosure, and dried filament.

The advanced operations configuration is intentionally declarative. It does
not change Klipper settings automatically. Backups, mesh health, Smart Level,
and watcher alerts are validated locally; native Moonraker/Klipper endpoints
and detected macros remain prerequisites.

The Siri/Home Assistant bridge is unavailable until printer-side pairing is
confirmed. Remote status remains read-only, and sensitive actions require a
fresh printer-displayed challenge plus a second confirmation on the screen.

## Known differences

Moonraker object names and Klipper macro names are configuration-dependent.
Official QIDI firmware updates may add, remove, or rename objects. Re-run the
probe after updates and keep the stock QIDI UI enabled until the result is
understood.

## Rollback

Use `sudo q2-display-mode enable-qidi` to return to the stock UI immediately.
The installer also keeps an on-printer backup and automatically restores the
stock UI when the display service fails.
