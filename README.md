<p align="center">
  <img src="assets/klipperscreen-splash.png" width="480" alt="KlipperScreen on QIDI Q2">
</p>

<h1 align="center">KlipperScreen on QIDI Q2</h1>

<p align="center">
  A proper interface on the stock display. No Raspberry Pi, second screen,
  or ceremonial Android tablet required.
</p>

<p align="center">
  <img alt="QIDI Q2" src="https://img.shields.io/badge/QIDI-Q2-ed6500">
  <img alt="Firmware 01.01.02.03" src="https://img.shields.io/badge/firmware-01.01.02.03-009183">
  <img alt="Debian 11 ARM64" src="https://img.shields.io/badge/Debian_11-ARM64-ae007e">
  <img alt="Works on my printer" src="https://img.shields.io/badge/works_on-my_printer-a7e100">
  <img alt="AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-blue">
</p>

> [!WARNING]
> This is an unofficial project tested on a **QIDI Q2 running firmware
> `01.01.02.03`**. The installer deliberately refuses unknown firmware and
> active prints. A printer is a poor place for a confident “probably fine.”

## How did we get here?

The QIDI Q2 is a genuinely good printer: fast, enclosed, Klipper-powered, and
equipped with a perfectly decent stock display. It has almost everything.

Except KlipperScreen.

I did the responsible thing and searched for an existing solution. I found
guides for the Q1 Pro, Plus4, Raspberry Pi, old phones, and possibly a smart
fridge. For the Q2, the internet offered a tasteful silence.

That is how I became much more familiar with `rockchipdrmfb`, Goodix, Xvfb, and
the missing `/dev/tty0` than I had planned. The result is this repository: one
self-contained script, executed **on the printer itself**, that turns the stock
480×272 panel into a normal KlipperScreen.

## What works

- KlipperScreen runs directly on the stock Q2 display.
- Touch is calibrated, so buttons are pressed where the buttons actually are.
- A QIDI Q2 visual treatment uses the dark graphite material theme, teal active
  states, orange warnings, and a larger touch-friendly font.
- The camera panel works through the installed `libmpv` runtime.
- Wi-Fi can be configured from KlipperScreen's Network panel using the Q2's
  existing NetworkManager-backed wireless adapter.
- The control screen provides native jog, homing, extrusion, temperature, fan,
  lights, pause/resume/cancel, and motors-off actions when Moonraker exposes
  the corresponding objects.
- Optional load, unload, purge, and tool-selection buttons are shown only when
  matching Klipper macros are detected.
- A proper splash covers the black gap while GTK wakes up.
- The stock QIDI interface is kept intact.
- Swipe up from the bottom edge to open KlipperScreen.
- Swipe down from the top edge to return to the QIDI interface.
- A failed KlipperScreen startup automatically restores the stock UI.
- One script installs the whole stack and makes it survive a reboot.

<p align="center">
  <img src="docs/images/main-screen.png" width="720" alt="KlipperScreen main screen on QIDI Q2">
</p>

## Videos

### Full KlipperScreen tour

https://github.com/user-attachments/assets/28980aa5-b12a-4b6f-87f2-05b89f413b6e

Startup splash, touch navigation, panels, and the camera view—all on the stock
Q2 display.

### Returning to the stock QIDI UI

https://github.com/user-attachments/assets/62a5223e-957d-4693-8391-08c91164f8c1

The other half of the escape hatch.

Both demos are silent, fast-start H.264 at 1280×720. The originals were 1080p
HEVC phone footage; excellent for a camera roll, less excellent for browsers
and Git history.

## Installation

Windows, macOS, and Linux disagree about many things. Fortunately, all three
can speak SSH to a printer.

### Before you begin

- The printer must be a **QIDI Q2 running firmware `01.01.02.03`**.
- The printer must be fully booted, idle, and not installing a firmware update.
- The computer and printer must be on the same local network.
- The printer needs internet access while the installer downloads its pinned
  dependencies.
- Keep the stock screen available during installation. Do not power the printer
  off because a progress line paused long enough to make you suspicious.

The verified factory SSH credentials are:

| Field | Factory value |
|---|---|
| SSH user | `mks` |
| SSH password | `makerbase` |
| `sudo` password | `makerbase` |

If you changed these credentials, use your own values. Passwords are not shown
while you type them in a terminal—not even dots. That is normal Unix behavior,
not the printer judging your typing.

### 1. Download the repository

The simplest route:

1. Click **Code**, then **Download ZIP** on this repository page.
2. Extract the ZIP.
3. Open the extracted `klipperscreen-q2-main` folder.

If Git is already installed and authenticated with GitHub, cloning works too:

```sh
git clone https://github.com/jeecrypt/klipperscreen-q2.git
cd klipperscreen-q2
```

The two files used for installation are:

```text
install-klipperscreen-q2-on-printer.sh
install-klipperscreen-q2-on-printer.sh.sha256
```

Do not open and resave the shell script in a random text editor. The installer
likes Unix line endings and has already had enough adventure for one project.

### 2. Find the printer IP address

Open the network page on the Q2 display and note its IPv4 address. It will
usually look similar to `192.168.1.123`.

Every command below uses `PRINTER_IP` as a placeholder. Replace it with the
actual address:

```text
mks@PRINTER_IP     becomes     mks@192.168.1.123
```

The address may change after a router or printer restart unless the router has
a DHCP reservation for the Q2.

### 3. Check SSH on your computer

#### Windows 10 or 11

Open **PowerShell** or **Windows Terminal** and run:

```powershell
Get-Command ssh
Get-Command scp
```

If both commands print a path, continue. If either command is missing, install
**OpenSSH Client** from one of these locations:

```text
Windows 11: Settings → System → Optional Features → View features
Windows 10: Settings → Apps → Optional features → Add a feature
```

Users of Git Bash or WSL may follow the macOS/Linux commands instead.

#### macOS

Open **Terminal**. SSH and SCP are included with macOS:

```sh
command -v ssh scp
```

#### Linux

Open a terminal and check for both commands:

```sh
command -v ssh scp
```

Most distributions install them by default. On Debian or Ubuntu, the missing
package is:

```sh
sudo apt install openssh-client
```

### 4. Make the first SSH connection

The command is the same on every operating system:

```sh
ssh mks@PRINTER_IP
```

On the first connection, SSH asks whether you trust the printer host key. Check
that the IP is your Q2, type `yes`, and press Enter. Then enter the SSH password.

If the login succeeds, the prompt changes to the printer shell. Type:

```sh
exit
```

That first handshake saves the host key now, so SCP will not interrupt the
upload with a surprise identity crisis later.

### 5. Upload the installer

First open a terminal **inside the extracted or cloned repository folder**.

#### Windows PowerShell

In File Explorer, open the repository folder, right-click empty space, and
choose **Open in Terminal**. Then run this as one line:

```powershell
scp .\install-klipperscreen-q2-on-printer.sh .\install-klipperscreen-q2-on-printer.sh.sha256 mks@PRINTER_IP:/home/qidi/
```

#### macOS or Linux

Change to the repository directory and run:

```sh
scp \
  install-klipperscreen-q2-on-printer.sh \
  install-klipperscreen-q2-on-printer.sh.sha256 \
  mks@PRINTER_IP:/home/qidi/
```

The installer embeds the read-only Moonraker feature probe for fresh installs.
The helper scripts are uploaded separately only when using the existing-install
update flow below.

Before KlipperScreen starts, the launcher runs the probe and atomically writes
`/run/klipperscreen-q2/capabilities.env`. Optional filament macro gates are
enabled only for exact detected `LOAD_FILAMENT`, `UNLOAD_FILAMENT`,
`PURGE_FILAMENT`, or `SELECT_TOOL` objects; probe errors and unknown values
disable every optional gate.

### Optional local AI watchdog

`tools/printer_ai_watchdog.py` is an observe-only-by-default service. Copy
`config/printer-ai-watchdog.json` to `/etc/printer-ai-watchdog.json`, adjust
the authenticated/local Moonraker endpoint as appropriate, and install
`config/printer-ai-watchdog.service`. AI is never an initiator: no Claude,
Ollama, or other model may start a printer operation. Ollama is consulted only
after an authenticated Siri/Home Assistant bridge request explicitly names an
operation (`status`, `check`, `pause`, or `firmware_restart`). Status/check are
read-only. Pause/restart additionally require the printer-side confirmation and
the request operation must exactly match the model action. Direct watchdog
actions are denied even if `action_policy.enabled` is accidentally enabled.
Thermal limits are checked deterministically for observation and audit only;
they do not autonomously pause or restart the printer. Ollama output must be
strict JSON and free-form text is rejected. The service never executes
arbitrary macros or shell commands, and the JSONL audit log is secret-redacted
and fsync'd per record.

Enter the SSH password when prompted. A successful upload returns to the local
prompt without drama, fireworks, or a certificate suitable for framing.

### 6. Connect to the printer and verify the upload

```sh
ssh mks@PRINTER_IP
cd /home/qidi
ls -lh \
  install-klipperscreen-q2-on-printer.sh \
  install-klipperscreen-q2-on-printer.sh.sha256
sha256sum -c install-klipperscreen-q2-on-printer.sh.sha256
```

The checksum command must report:

```text
install-klipperscreen-q2-on-printer.sh: OK
```

If it reports `FAILED`, do not run the installer. Upload both files again from
a fresh repository download.

### 7. Install KlipperScreen

Everything from this point runs **on the QIDI Q2**:

```sh
sudo bash /home/qidi/install-klipperscreen-q2-on-printer.sh install
```

Enter the `sudo` password when prompted. Leave the SSH window open until the
script finishes.

The installer will:

1. verify the model, firmware, architecture, framebuffer, and print state;
2. create an initial on-printer backup;
3. install a pinned KlipperScreen revision, GTK theme polish, and runtime
   dependencies including NetworkManager;
4. install the framebuffer bridge, touch calibration, splash, and gestures;
5. probe the display stack on a separate X display;
6. enable KlipperScreen while keeping an emergency route back to QIDI.

The first launch takes a few seconds. The logo is not merely decorative: it
means the printer is alive and GTK is gathering its thoughts.

### Wi-Fi setup from KlipperScreen

After installation, open **Menu → Network**. The panel can enable or disable
the wireless radio, scan for nearby access points, and connect to a secured
network. The installer enables `NetworkManager.service`, which is the service
used by the upstream KlipperScreen Network panel; it does not replace the
QIDI client or change Moonraker's configuration.

If no wireless networks are listed, verify the service over SSH:

```sh
systemctl is-active NetworkManager.service
nmcli device status
```

The printer must be on a normal LAN during setup. Guest networks with client
isolation may allow internet access but prevent SSH, Moonraker, or the stock
QIDI UI from reaching the printer.

### 8. Verify the result

Still connected over SSH, run:

```sh
sudo bash /home/qidi/install-klipperscreen-q2-on-printer.sh status
systemctl is-active KlipperScreen.service
systemctl is-active q2-display-gesture.service
```

Both services should report `active`. Then test the screen:

1. swipe from the top edge to the bottom to return to the stock QIDI UI;
2. swipe from the bottom edge to the top to open KlipperScreen again.

Type `exit` when finished.

### SSH problems before installation

- **Connection timed out:** confirm the IP, keep both devices on the same LAN,
  and avoid guest Wi-Fi or access-point isolation.
- **Connection refused:** wait for the Q2 to finish booting and try again.
- **Permission denied:** use `mks` and the current printer SSH password.
- **Host identification has changed:** first confirm that the IP still belongs
  to your Q2. If the printer was reset or reflashed, remove the old key with
  `ssh-keygen -R PRINTER_IP`, then reconnect.
- **`scp` cannot find the files:** the terminal is not open in the repository
  folder. Change directory or use the full local file paths.

Installation and display recovery problems live in
[Troubleshooting and recovery](docs/TROUBLESHOOTING.md).

## Display controls

| Action | Result |
|---|---|
| Swipe from the bottom edge to the top | Open KlipperScreen |
| Swipe from the top edge to the bottom | Return to the QIDI UI |
| `sudo q2-display-mode klipperscreen` | Switch to KlipperScreen now |
| `sudo q2-display-mode qidi` | Switch to QIDI now |
| `sudo q2-display-mode enable-klipperscreen` | Boot into KlipperScreen |
| `sudo q2-display-mode enable-qidi` | Boot into the stock UI |
| `sudo q2-display-mode status` | Show the active and boot UIs |

## Control and filament safety

The **Move**, **Extrude**, **Temperature**, **Fan**, **Print**, and **Machine**
panels are upstream KlipperScreen controls. The configured Q2 presets are
`0.1, 1, 10, 50 mm` for movement and `5, 10, 25, 50 mm` for extrusion; change
them only after validating the machine's limits. Never jog or extrude while a
person, tool, or loose filament is in the motion path.

Before using optional load/unload/purge/material buttons, check the read-only
feature report:

```sh
python3 /home/qidi/q2-moonraker-features.py --json
```

The probe only reads Moonraker's object list. It does not issue G-code. Missing
objects or macros are treated as unsupported. The probe is a report and safety
check; it does not rewrite KlipperScreen configuration or invent macro buttons.
Upstream KlipperScreen panels gate their native controls from live Moonraker
objects. Optional QIDI macros must remain explicitly configured and confirmed
by the operator.

### Filament

The dedicated **Filament** workflow uses known material profiles rather than
accepting arbitrary temperatures. Select a profile to review its nozzle and bed
targets before applying them through the normal KlipperScreen temperature
controls:

| Profile | Nozzle | Bed |
|---|---:|---:|
| PLA | 220 °C | 60 °C |
| PETG | 245 °C | 80 °C |
| ABS / ASA | 260 °C | 100 °C |
| TPU | 230 °C | 50 °C |
| PA6-GF / PA6-CF | 270 °C | 90 °C |
| PAHT | 280 °C | 100 °C |

PA6-GF, PA6-CF, and PAHT require a hardened hotend, enclosure, and dried
filament. These are conservative targets for review, not automatic hardware or
slicer changes.

The mapping is available without a printer connection:

```sh
python3 /home/qidi/q2-filament.py --profile petg
```

Load, unload, purge, and tool-selection buttons remain conditional on detected
Klipper macros. The profile helper never emits G-code and unknown materials are
rejected.

### Smart purge and collision protection

The rear-waste-chute **Smart Purge** button is disabled until measured chute
geometry is configured in `config/q2-feature-hooks.conf`. There are no fixed Q2
coordinates in this repository.

### Advanced operations: backup, speed, mesh, and watcher

Before applying any local macro/configuration change, make a timestamped,
non-overwriting archive of `printer_data`; retain at least the five newest
archives. Restore only after stopping KlipperScreen and reviewing the archive:

```sh
sudo tar -czf "/home/qidi/q2-backups/qidi-q2-config-$(date -u +%Y%m%dT%H%M%SZ).tar.gz" \
  -C /home/qidi printer_data
sudo q2-display-mode enable-qidi
# Extract a reviewed archive to a staging directory before restoring files.
```

The speed controls in `config/q2-advanced-operations.conf` are limits only;
the UI must use supported Klipper/Moonraker native settings and reject values
outside those limits. The Bed Mesh tile is `good`, `bad`, or `unknown` based
on the complete reported matrix, tolerance, and freshness; missing or stale
data never triggers leveling. Smart Level requires detected `Z_TILT_ADJUST`
and `BED_MESH_CALIBRATE`, a toolhead object, and explicit confirmation.

The optional camera watcher integration has no bundled AI model. When a local
watcher is configured, it may request the authenticated Moonraker `PAUSE`
macro and send an authenticated HTTPS Home Assistant/webhook alert. Otherwise
the watcher remains unavailable. `docs/apple-shortcut-qidi-q2.json` is an
iPhone Shortcut template for status, pause/alert, and confirmed macro actions.

### Locked Siri/Home Assistant bridge

Remote Siri or Shortcut commands are locked until the phone pairs with the
printer-specific identity. KlipperScreen shows `Locked / unpaired`,
`Pending confirmation`, `Paired`, or `Challenge pending`; the printer displays
the short-lived pairing code during pairing and a fresh challenge for each
sensitive action. Pairing codes expire, are printer-bound, rate-limited after
five failures, and never logged or committed. Status is read-only and requires
pairing. Motion, heating, purge, Smart Level, pause, and cancel require a
second explicit confirmation on the printer UI; stale, replayed, or
mismatched-printer requests are rejected. Revoke pairing from the printer
before changing phones or webhook credentials.

The Shortcut artifact uses placeholders only. Store the bearer token in the
phone/Home Assistant secret store, not in this repository. The bridge must
authenticate to Moonraker and must not expose an unauthenticated webhook.
Replace placeholders in the phone only and never commit a token.

### Monitoring and live state

The Shortcut template describes one bounded five-minute check while the printer
is printing. iOS may suspend or stop repeated Shortcut execution, so it is not
an endless monitoring loop. For continuous monitoring, import
`docs/home-assistant-qidi-q2-monitor.yaml`, configure an authenticated
`rest_command`, and use `input_boolean.qidi_q2_monitoring` as the stop switch.
The automation stops when the state is idle, complete, error, or offline.
Alerts are deduplicated and limited to watcher misprint/spaghetti findings,
pause, thermal/failure states, or an offline printer.

The live state tile uses existing Moonraker polling/events for state, target and
actual temperatures, progress, complete mesh health, and camera/watcher
availability. Idle, heating, printing, paused, completed, error, and offline
states include a label/icon as well as a high-contrast color. Missing or stale
mesh and unavailable camera/watcher data are explicitly shown as Unknown or
Unavailable. The validation path requires a homed printer,
enabled soft limits, configured rear-zone and corner margins, and a safe Z
clearance before it can produce a `PURGE_FILAMENT` command. Confirmation is
required for the final motion/heating action; dry-run validation never emits
G-code. Leave the feature disabled when the chute position or printer limits
are unknown. The same guards apply to rear parking, screw-tilt, bed-mesh, and
KAMP purge hooks.

### Camera

The **Camera** section continues to use KlipperScreen's existing `libmpv`
path. It is available only when both a `/dev/video*` device and the installed
`libmpv` runtime are present; otherwise the section should stay hidden:

```sh
python3 /home/qidi/q2-moonraker-features.py --json
```

No camera device is assumed, and no camera stream is opened by the probe.

## Updating an existing installation

Run these commands from a computer with SSH access. They are idempotent and
leave the stock UI available:

```sh
git clone https://github.com/sowavy234/qidi-q2-klipperscreen.git
cd qidi-q2-klipperscreen
scp install-klipperscreen-q2-on-printer.sh \
    install-klipperscreen-q2-on-printer.sh.sha256 \
    tools/q2-moonraker-features.py \
    tools/q2-filament.py \
    tools/q2-safety.py \
    tools/q2-operations.py \
    tools/q2-monitor.py \
    tools/q2-bridge-auth.py \
    config/q2-feature-hooks.conf \
    config/q2-advanced-operations.conf \
mks@PRINTER_IP:/home/qidi/
ssh mks@PRINTER_IP \
  'cd /home/qidi && sha256sum -c install-klipperscreen-q2-on-printer.sh.sha256'
ssh mks@PRINTER_IP \
  'sudo bash /home/qidi/install-klipperscreen-q2-on-printer.sh install --no-enable'
ssh mks@PRINTER_IP 'sudo q2-display-mode klipperscreen'
ssh mks@PRINTER_IP 'sudo q2-display-mode status'
```

The optional helper/config files are read-only probes and templates; the
installer does not silently apply their macro names or speed limits. Review
and integrate them through the supported Moonraker/Klipper configuration after
the installer-created backup.

This temporarily selects KlipperScreen so the new screen and controls can be
checked while the stock QIDI UI remains the rollback choice at boot. After
checking the screen and controls, enable it at boot:

```sh
ssh mks@PRINTER_IP \
  'sudo bash /home/qidi/install-klipperscreen-q2-on-printer.sh klipperscreen'
```

If anything is wrong, roll back immediately:

```sh
ssh mks@PRINTER_IP 'sudo q2-display-mode enable-qidi'
```

The installer also restores the stock UI after a failed display startup.
`COMPATIBILITY_REPORT.md` documents the verified firmware and object matrix.

Gestures run in a separate service and do not depend on whichever UI happens to
be visible. A casual short swipe does not count: the stroke must begin at an
edge, cross most of the panel, and remain mostly vertical.

## Installer commands

```sh
# Install and make KlipperScreen the boot UI
sudo bash install-klipperscreen-q2-on-printer.sh install

# Install everything but keep QIDI as the boot UI
sudo bash install-klipperscreen-q2-on-printer.sh install --no-enable

# Show status
sudo bash install-klipperscreen-q2-on-printer.sh status

# Restore the stock UI now and on future boots
sudo bash install-klipperscreen-q2-on-printer.sh stock

# Enable KlipperScreen again now and on future boots
sudo bash install-klipperscreen-q2-on-printer.sh klipperscreen
```

`--force` exists for development on unverified firmware. If you think you need
it, what you almost certainly need first is a backup.

## Language

KlipperScreen defaults to English. The stock QIDI client does not expose a
stable language preference file on the verified firmware, and reverse
engineering proprietary runtime state just to guess a locale felt like the
wrong kind of clever. The language can be changed normally from KlipperScreen
settings after installation.

## Why is there a framebuffer bridge?

Regular KlipperScreen expects a regular Linux display stack. The Q2 kernel
provides DRM and `/dev/fb0`, but no virtual terminals such as `/dev/tty0` or
`/dev/tty1`. Debian Xorg therefore exits in `xf86OpenConsole`.

The route from GTK to pixels looks like this:

```text
KlipperScreen
    ↓
Xvfb :0, 480×272
    ↓
q2-x11-fb-bridge
    ├── frames → /dev/fb0
    └── Goodix touch → XTEST → KlipperScreen

Goodix touch → q2-display-gesture → q2-display-mode
```

The bridge is written in C, built for ARM64, and embedded in the installer
alongside its source and checksum. Until GTK paints a meaningful frame, the
bridge displays the splash. No magic is involved—just enough engineering to
look suspiciously like magic from a safe distance.

Read the full [architecture notes](docs/ARCHITECTURE.md).

## Compatibility

| Component | Verified configuration |
|---|---|
| Printer | QIDI Q2 |
| Firmware | `qd-q2-system 01.01.02.03` |
| OS | Debian 11 Bullseye |
| Architecture | ARM64, Rockchip RK3308B-S |
| Display | `rockchipdrmfb`, 480×272, 32 bpp |
| Touch | Goodix Capacitive TouchScreen, `/dev/input/event0` |
| KlipperScreen | commit `ed40799f92f8a5044082aee75b832a9e97084c7f` |

Other firmware versions are unverified, even when the number differs by one
apparently harmless digit. Vendors are remarkably good at hiding adventures
inside harmless digits.

## If something goes sideways

The shortest route home:

```sh
sudo bash /home/qidi/install-klipperscreen-q2-on-printer.sh stock
```

Or use the installed helper directly:

```sh
sudo q2-display-mode enable-qidi
```

The stock QIDI Client is never deleted. `KlipperScreen.service` is also wired to
`q2-display-fallback.service`; if the new display stack fails, the system tries
to restore the original UI automatically.

Useful logs:

```sh
sudo journalctl -u KlipperScreen.service -b
tail -f /home/qidi/printer_data/logs/KlipperScreen.log
sudo journalctl -u q2-display-gesture.service -b
```

See [troubleshooting and recovery](docs/TROUBLESHOOTING.md) for more.

## Repository map

| Path | Purpose |
|---|---|
| `install-klipperscreen-q2-on-printer.sh` | The self-contained installer and main character |
| `bridge/` | X11 → framebuffer and touch → XTEST |
| `gesture/` | Independent full-screen swipe recognizer |
| `bin/` | Display stack launcher and manual UI switching |
| `systemd/` | Main service, fallback, and gesture daemon |
| `config/` | KlipperScreen config and measured Goodix calibration |
| `assets/` | Splash source, preview, and framebuffer-ready pixels |
| `docs/media/` | Browser-friendly demo videos |
| `tools/` | Physical display test and touch calibration helpers |

## Development

```sh
make check
```

The check validates shell syntax, the installer checksum, embedded payloads,
and C sources. Building the bridge on Debian requires X11 development headers;
CI installs them automatically.

Before experimenting with the display stack, read
[CONTRIBUTING.md](CONTRIBUTING.md)—especially the part about why testing it
during a print is a creative but poor decision.

## Ramen and coffee fund

This project is free. Ramen, coffee, and late-night arguments with framebuffer
orientation remain stubbornly non-free.

If this project rescued your Q2 from stock-screen claustrophobia and you want
to feed the geek behind it, the following addresses work:

**Bitcoin (BTC)**

```text
bc1qeme3jqsyedx7feeuyudppl8xuuetnrq7axu4ql
```

**Ethereum (ETH, ERC-20 USDT, or ERC-20 USDC)**

```text
0x1CeefD941Bd801279B5152f8e0eed5253926676D
```

**Litecoin (LTC)**

```text
ltc1qfgaw6xjy39606a6mcmlt4mzzk6e8jjqxmjnwjk
```

**Tron (TRX, TRC-20 USDT, or TRC-20 USDC)**

```text
TSkE5HrxEXybYk8dU6fGvgXjyij8LmS3M2
```

Double-check both the address and network before sending. Blockchains remain
famously underfunded in the Undo button department. For anything larger than
your acceptable contribution to the void, send a tiny test transaction first.

## Credits

- [KlipperScreen](https://github.com/KlipperScreen/KlipperScreen), for the
  interface that started this whole detour;
- [Klipper](https://github.com/Klipper3d/klipper) and
  [Moonraker](https://github.com/Arksine/moonraker), for the ecosystem;
- people who publish source code and logs instead of saying “works for me.”

This project is not affiliated with QIDI Tech and is not an official
KlipperScreen product. The splash icon is based on a KlipperScreen asset.

## License

[GNU AGPL v3.0 or later](LICENSE). Fork it, improve it, and please include the
printer model in bug reports. Telepathy is not currently listed as a
dependency.
