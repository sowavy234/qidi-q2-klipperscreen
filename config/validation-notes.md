# Validation notes

The repository has no live-printer test fixture. Validation is therefore
static: shell syntax, embedded payload integrity, Python unit tests, and
Moonraker feature-detection tests run without network access.

The feature probe is deliberately read-only. It never sends G-code and never
enables a macro. Temperature and motion safety remain enforced by Klipper and
the upstream KlipperScreen controls.
