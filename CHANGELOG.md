# Changelog

## Unreleased

- Package the read-only Moonraker feature probe in fresh installer installs;
  missing optional helper modules now report unavailable camera support instead
  of failing installation.
- Compile probe results into a private, atomic launcher capability file before
  starting KlipperScreen; optional filament macro gates fail closed on errors.
- Add an opt-in, observe-only local Ollama/Moonraker watchdog with deterministic
  thermal guards, strict action validation, cooldowns, redacted audit logging,
  and a hardened systemd template.

This file records public installer releases. The format is inspired by
[Keep a Changelog](https://keepachangelog.com/), minus the fiction that a home
project emerges from the workshop with a perfect release process.

## [1.4.0] — 2026-07-24

### Added

- Added NetworkManager provisioning so KlipperScreen's Wi-Fi panel works on
  the QIDI Q2 hardware.
- Added a QIDI Q2 material-darker theme layer with larger touch targets and
  teal/orange status accents.

## [2.0.0] — 2026-09-14

### Added

- Added a QIDI Q2 control release based on upstream KlipperScreen's native
  motion, homing, extrusion, temperature, fan, lighting, and print-state
  panels.
- Added conservative jog/extrusion step presets for the 480×272 touch panel.
- Added a read-only Moonraker feature probe that detects optional filament
  macros and disables unsupported control groups instead of guessing.
- Added compatibility, validation, setup, and rollback documentation for the
  verified QIDI Q2 firmware image.

### Changed

- Added a dedicated filament-profile workflow with validated PLA, PETG, ABS,
  ASA, and TPU nozzle/bed target mappings.
- Added camera capability detection that requires both a video device and the
  existing `libmpv` runtime before the Camera section is shown.
- Added opt-in rear-chute smart-purge validation with configurable geometry,
  soft-limit, homing, Z-clearance, rear-zone, and corner-collision guards.
- Added dry-run helpers for timestamped non-overwriting configuration backups,
  speed bounds, full bed-mesh health classification, guarded Smart Level, and
  authenticated watcher alert payloads.
- Added a placeholder-only iPhone Shortcut artifact for the Home Assistant or
  HTTPS webhook bridge.
- Added bounded five-minute monitoring actions, a Home Assistant continuous
  automation blueprint, deduplicated problem alerts, and accessible live state
  color/label classes for printer, mesh, and watcher status.
- Locked the Siri/Home Assistant bridge behind printer-bound pairing codes,
  expiring challenges, rate limiting, and second confirmation for
  safety-critical actions.
- Hardened bridge authorization to reject unknown actions and single-use
  pairing-code replay.
- Corrected Moonraker feature detection for homing, heated extruders, malformed
  responses, and the documented `SELECT_TOOL` macro. The setup guide now
  uploads the read-only probe and validates KlipperScreen before boot enablement.

## [1.3.2] — 2026-07-23

### Changed

- Made English the default KlipperScreen language.
- Turned the project into a clean, documented, CI-checked repository.
- Added browser-friendly 720p H.264 demo videos.

## [1.3.1] — 2026-07-23

### Fixed

- Corrected the framebuffer splash row order. The logo no longer auditions for
  Australian KlipperScreen on the physical Q2 panel.

## [1.3.0] — 2026-07-23

### Added

- Added a branded 480×272 startup splash.
- Kept the splash visible until GTK paints a meaningful frame.
- Added a 15-second safety timeout for a stalled display stack.

## [1.2.1] — 2026-07-23

### Changed

- Stopped ordinary taps from flooding the gesture daemon journal.

## [1.2.0] — 2026-07-23

### Added

- Added full-screen swipes between QIDI UI and KlipperScreen.
- Added an independent systemd gesture service.

## [1.0.0] — 2026-07-23

### Added

- Added self-contained KlipperScreen installation for the stock QIDI Q2 panel.
- Added Xvfb and the ARM64 framebuffer/input bridge.
- Added five-point Goodix calibration.
- Kept the stock QIDI Client with automatic failure fallback.
- Added firmware, print-state, APT plan, and SHA-256 safety checks.
