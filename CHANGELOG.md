# Changelog

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
