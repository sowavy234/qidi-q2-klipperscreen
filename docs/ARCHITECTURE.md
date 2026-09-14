# Architecture

## Goal

Run ordinary KlipperScreen on the stock ARM64 QIDI Q2 controller using its
existing LCD and Goodix touch panel, without deleting the QIDI Client.

## Why not regular Xorg?

The vendor kernel exposes DRM and `/dev/fb0`, but no Linux virtual terminals
such as `/dev/tty0` or `/dev/tty1`. Debian Xorg expects a VT and exits in
`xf86OpenConsole`.

The solution uses a headless X server:

```text
KlipperScreen (GTK)
        │
        ▼
Xvfb :0 — 480×272×24
        │ XShmGetImage
        ▼
q2-x11-fb-bridge
        │
        ├── RGB frame ───────────────► /dev/fb0
        │
        └── Goodix input ──► affine transform ──► XTEST
```

KlipperScreen's Network panel uses the pinned `sdbus_networkmanager` Python
client and the printer's system `NetworkManager.service`. The installer adds
the Debian NetworkManager package and enables the service without replacing
the vendor QIDI UI or its existing network configuration.

The bridge captures the X root window through MIT-SHM at 20 FPS and copies each
frame into the 32-bit `rockchipdrmfb`. The same process reads
`/dev/input/event0`, applies the measured affine matrix, and injects calibrated
coordinates through XTEST.

## Startup splash

Before GTK appears, the X root window is almost entirely black. The bridge
immediately writes a framebuffer-ready 480×272 BGRA splash, then continues
inspecting X11 frames. The splash disappears when:

- at least 600 ms has elapsed;
- the frame contains enough pixels that differ from its background;
- or a 15-second safety timeout expires.

This removes the black startup gap without hiding a stalled UI forever.

## UI switching

`q2-display-mode` ensures that only one UI owns the panel:

```text
qidi-client.service ◄──── q2-display-mode ────► KlipperScreen.service
                                                │
                                                └── OnFailure:
                                                    q2-display-fallback.service
```

The `qidi` and `klipperscreen` commands switch the current UI.
`enable-qidi` and `enable-klipperscreen` also change the boot selection.

## Gestures

`q2-display-gesture.service` reads Goodix multitouch events directly:

- start at the bottom edge and travel upward → `klipperscreen`;
- start at the top edge and travel downward → `qidi`.

The recognizer requires at least 180 px of mostly vertical travel over
120–2200 ms and applies a three-second cooldown. It does not grab the device
exclusively, so ordinary touch events still reach the active UI.

## Installer safety

Before making changes, the installer:

- verifies firmware, Debian, ARM64, framebuffer geometry, and touch device;
- asks Moonraker and Klipper whether a print is active;
- creates an initial backup;
- verifies every downloaded and embedded SHA-256;
- simulates APT and blocks changes to `libc`, `systemd`, and Xorg;
- probes the bridge on a separate Xvfb display;
- preserves the stock QIDI Client.
