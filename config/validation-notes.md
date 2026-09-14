# Validation notes

The repository has no live-printer test fixture. Validation is therefore
static: shell syntax, embedded payload integrity, Python unit tests, and
Moonraker feature-detection tests run without network access.

The feature probe is deliberately read-only. It never sends G-code and never
enables a macro. Temperature and motion safety remain enforced by Klipper and
the upstream KlipperScreen controls.

The advanced-hook validator is also dry-run only. It emits a candidate macro
string only after configured geometry, soft limits, homing, clearance, and
explicit confirmation checks pass. No live printer, watcher, camera stream, or
webhook was used.

Bridge authorization tests cover printer-bound pairing, expiry, replay and
identity rejection, rate limiting, and sensitive-action challenge gates.
