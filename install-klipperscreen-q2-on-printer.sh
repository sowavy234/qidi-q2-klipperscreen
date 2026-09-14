#!/bin/bash
#
# Standalone KlipperScreen installer for the stock QIDI Q2 controller.
#
# Run on the printer:
#   sudo bash install-klipperscreen-q2-on-printer.sh install
#
# Other actions:
#   sudo bash install-klipperscreen-q2-on-printer.sh status
#   sudo bash install-klipperscreen-q2-on-printer.sh stock
#   sudo bash install-klipperscreen-q2-on-printer.sh klipperscreen
#
set -Eeuo pipefail
IFS=$'\n\t'

readonly INSTALLER_VERSION="1.4.0"
readonly SUPPORTED_ARCH="arm64"
readonly SUPPORTED_OS="debian"
readonly SUPPORTED_OS_VERSION="11"
readonly SUPPORTED_FIRMWARE="01.01.02.03"
readonly EXPECTED_FB_SIZE="480,272"
readonly EXPECTED_TOUCH_NAME="Goodix Capacitive TouchScreen"

readonly KS_COMMIT="ed40799f92f8a5044082aee75b832a9e97084c7f"
readonly KS_ARCHIVE_URL="https://github.com/KlipperScreen/KlipperScreen/archive/${KS_COMMIT}.tar.gz"
readonly KS_ARCHIVE_SHA256="b6ad493c10d86b9b61ff6be9b27536946c421bd21563f40d1a50ca844188b08f"

# The vendor image holds xserver-common at this exact version. Installing the
# matching Xvfb package avoids upgrading the held QIDI display stack.
readonly XVFB_VERSION="2:1.20.11-1+deb11u10"
readonly XVFB_URL="https://snapshot.debian.org/file/9cb3610a1baa3347e3fbd94c2aedffe206a9f351"
readonly XVFB_SHA256="0ee0b6167cf6d2b53bdd47ea174bdda4e999b6f0a531c2dd2a6f924700050fbe"

readonly QIDI_HOME="/home/qidi"
readonly KS_DIR="${QIDI_HOME}/KlipperScreen"
readonly VENV_DIR="${QIDI_HOME}/.KlipperScreen-env"
readonly STATE_DIR="/var/lib/klipperscreen-q2"
readonly BACKUP_ROOT="${QIDI_HOME}/klipperscreen-q2-backups"
readonly LIBEXEC_DIR="/usr/local/libexec/q2"
readonly TOUCH_MATRIX="0.993734337,0.013657054,1.013045282,-0.003869942,1.045389229,-7.131267566"
readonly BRIDGE_BINARY_SHA256="7c72276d247459aef6c3f8753e36f52c327ccdf10885ea800ebbf57db091cf4f"
readonly GESTURE_BINARY_SHA256="f46b6ff6ee32191a2fbe5ea6fa15d01b048028726e5e62ba23980cbfc423ed66"
readonly SPLASH_BINARY_SHA256="88c4a7ca24b915a1f56a8fffde066699adc4f8e5584d6167c8879bc3f9717320"

action="install"
force=0
enable_at_boot=1
work_dir=""
backup_dir=""
display_was_switched=0

log() {
    printf '[q2-klipperscreen] %s\n' "$*"
}

warn() {
    printf '[q2-klipperscreen] WARNING: %s\n' "$*" >&2
}

die() {
    printf '[q2-klipperscreen] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  sudo bash install-klipperscreen-q2-on-printer.sh [action] [options]

Actions:
  install         Install, test, and enable KlipperScreen (default)
  status          Show installed version and active/boot display UI
  stock           Make the stock QIDI UI active now and at boot
  klipperscreen   Make KlipperScreen active now and at boot

Options for install:
  --no-enable     Install and test, but leave the stock QIDI UI enabled
  --force         Allow an unverified firmware/platform combination
  -h, --help      Show this help

Supported reference system:
  QIDI Q2 firmware 01.01.02.03, Debian 11 arm64, 480x272 Goodix display.
EOF
}

parse_arguments() {
    if (($# > 0)) && [[ "$1" != -* ]]; then
        action="$1"
        shift
    fi
    while (($# > 0)); do
        case "$1" in
            --no-enable)
                enable_at_boot=0
                ;;
            --force)
                force=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
        shift
    done
    case "$action" in
        install|status|stock|klipperscreen)
            ;;
        *)
            die "Unknown action: $action"
            ;;
    esac
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] ||
        die "Run this script as root: sudo bash $0 $action"
}

cleanup() {
    local status=$?
    if [[ -n "$work_dir" && -d "$work_dir" ]]; then
        rm -rf -- "$work_dir"
    fi
    if ((status != 0 && display_was_switched == 1)); then
        warn "Installation failed; restoring the stock QIDI interface."
        systemctl disable KlipperScreen.service >/dev/null 2>&1 || true
        systemctl enable qidi-client.service >/dev/null 2>&1 || true
        systemctl stop KlipperScreen.service >/dev/null 2>&1 || true
        systemctl restart qidi-client.service >/dev/null 2>&1 || true
    fi
    exit "$status"
}

on_error() {
    local status=$?
    local line=$1
    warn "Command failed at line ${line} (status ${status})."
    return "$status"
}

download_verified() {
    local url=$1
    local destination=$2
    local expected_sha=$3
    local temporary="${destination}.part"

    log "Downloading $(basename "$destination")"
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --retry 4 --retry-delay 2 \
            --connect-timeout 20 --output "$temporary" "$url"
    else
        python3 - "$url" "$temporary" <<'PY'
import sys
import urllib.request

urllib.request.urlretrieve(sys.argv[1], sys.argv[2])
PY
    fi
    printf '%s  %s\n' "$expected_sha" "$temporary" | sha256sum --check --status ||
        die "SHA-256 check failed for $url"
    mv -f -- "$temporary" "$destination"
}

check_print_state() {
    local state
    state="$(
        python3 - <<'PY' 2>/dev/null || true
import json
import urllib.request

with urllib.request.urlopen(
    "http://127.0.0.1:7125/printer/objects/query?print_stats",
    timeout=2,
) as response:
    data = json.load(response)
print(data["result"]["status"]["print_stats"]["state"])
PY
    )"
    if [[ "$state" == "printing" || "$state" == "paused" ]]; then
        if ((force == 0)); then
            die "The printer state is '$state'. Finish/cancel the job first."
        fi
        warn "Proceeding while printer state is '$state' because --force was used."
    fi
}

platform_mismatch() {
    local message=$1
    if ((force == 1)); then
        warn "$message"
    else
        die "$message Use --force only after checking compatibility."
    fi
}

verify_platform() {
    local architecture
    local firmware
    local framebuffer_size
    local touchscreen_name

    architecture="$(dpkg --print-architecture)"
    [[ "$architecture" == "$SUPPORTED_ARCH" ]] ||
        platform_mismatch "Expected ${SUPPORTED_ARCH}, found ${architecture}."

    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "$SUPPORTED_OS" && "${VERSION_ID:-}" == "$SUPPORTED_OS_VERSION" ]] ||
        platform_mismatch \
            "Expected Debian 11, found ${ID:-unknown} ${VERSION_ID:-unknown}."

    firmware="$(dpkg-query -W -f='${Version}' qd-q2-system 2>/dev/null || true)"
    [[ "$firmware" == "$SUPPORTED_FIRMWARE" ]] ||
        platform_mismatch \
            "Expected Q2 firmware ${SUPPORTED_FIRMWARE}, found ${firmware:-unknown}."

    [[ -e /dev/fb0 ]] || platform_mismatch "/dev/fb0 is missing."
    framebuffer_size="$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true)"
    [[ "$framebuffer_size" == "$EXPECTED_FB_SIZE" ]] ||
        platform_mismatch \
            "Expected framebuffer ${EXPECTED_FB_SIZE}, found ${framebuffer_size:-unknown}."

    [[ -e /dev/input/event0 ]] || platform_mismatch "/dev/input/event0 is missing."
    touchscreen_name="$(cat /sys/class/input/event0/device/name 2>/dev/null || true)"
    [[ "$touchscreen_name" == "$EXPECTED_TOUCH_NAME" ]] ||
        platform_mismatch \
            "Expected '${EXPECTED_TOUCH_NAME}', found '${touchscreen_name:-unknown}'."

    systemctl cat qidi-client.service >/dev/null 2>&1 ||
        platform_mismatch "qidi-client.service is missing."
    getent passwd qidi >/dev/null || platform_mismatch "The qidi user is missing."
    command -v gcc >/dev/null 2>&1 ||
        platform_mismatch "The stock GCC compiler is missing."

    log "Platform verified: QIDI Q2 ${firmware}, Debian 11 ${architecture}."
}

make_initial_backup() {
    local stamp
    local archive
    local -a paths=()
    local path

    install -d -m 0755 "$STATE_DIR" "$BACKUP_ROOT"
    if [[ -s "${STATE_DIR}/initial-backup" ]]; then
        archive="$(cat "${STATE_DIR}/initial-backup")"
        if [[ -s "$archive" ]]; then
            log "Initial backup already exists: $archive"
            backup_dir="$(dirname "$archive")"
            return
        fi
    fi

    stamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="${BACKUP_ROOT}/before-klipperscreen-${stamp}"
    install -d -m 0755 "$backup_dir"

    for path in \
        home/qidi/QIDI_Client \
        home/qidi/printer_data/config \
        etc/systemd/system/qidi-client.service \
        etc/X11 \
        usr/local/sbin/q2-display-mode \
        usr/local/libexec/q2 \
        etc/systemd/system/KlipperScreen.service \
        etc/systemd/system/q2-display-fallback.service \
        etc/systemd/system/q2-display-gesture.service \
        etc/default/klipperscreen-q2; do
        [[ -e "/$path" ]] && paths+=("$path")
    done

    dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Status}\n' \
        >"${backup_dir}/packages.tsv"
    systemctl cat qidi-client.service \
        >"${backup_dir}/qidi-client.service.txt" 2>&1 || true
    uname -a >"${backup_dir}/uname.txt"
    dpkg-query -W -f='${Version}\n' qd-q2-system \
        >"${backup_dir}/q2-firmware-version.txt" 2>/dev/null || true

    archive="${backup_dir}/live-system-backup.tar.gz"
    log "Creating initial backup: $archive"
    tar -C / -czpf "$archive" "${paths[@]}"
    tar -tzf "$archive" >/dev/null
    sha256sum "$archive" >"${archive}.sha256"
    printf '%s\n' "$archive" >"${STATE_DIR}/initial-backup"
    chown -R qidi:qidi "$BACKUP_ROOT"
}

install_system_packages() {
    local installed_xvfb
    local installed_common
    local apt_plan
    local package
    local source_file
    local temporary_sources="${work_dir}/apt-sources.list"
    local -a missing_packages=()
    local -a source_files=()
    local -a apt_command=()

    export DEBIAN_FRONTEND=noninteractive

    for package in python3-venv libmpv1 network-manager; do
        if [[ "$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)" != "installed" ]]; then
            missing_packages+=("$package")
        fi
    done
    if ! python3 - <<'PY' >/dev/null 2>&1
import cairo
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
PY
    then
        for package in python3-gi python3-gi-cairo python3-cairo gir1.2-gtk-3.0 librsvg2-common; do
            if [[ "$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)" != "installed" ]]; then
                missing_packages+=("$package")
            fi
        done
    fi

    if ((${#missing_packages[@]} > 0)); then
        [[ -f /etc/apt/sources.list ]] && source_files+=(/etc/apt/sources.list)
        while IFS= read -r -d '' source_file; do
            source_files+=("$source_file")
        done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f -name '*.list' -print0 2>/dev/null)
        ((${#source_files[@]} > 0)) || die "No APT sources were found."

        # The stock image still references bullseye-backports, which was removed
        # from normal mirrors after Bullseye reached oldoldstable. Use a temporary
        # filtered list rather than modifying the printer's vendor configuration.
        awk '
            /^[[:space:]]*deb(-src)?[[:space:]].*bullseye-backports/ { next }
            { print }
        ' "${source_files[@]}" >"$temporary_sources"
        grep -Eq '^[[:space:]]*deb[[:space:]]' "$temporary_sources" ||
            die "The filtered APT source list is empty."

        apt_command=(
            apt-get
            -o "Dir::Etc::sourcelist=${temporary_sources}"
            -o "Dir::Etc::sourceparts=-"
        )

        log "Refreshing Debian package metadata (ignoring retired bullseye-backports)."
        "${apt_command[@]}" update
        apt_plan="$("${apt_command[@]}" --simulate install --no-install-recommends "${missing_packages[@]}")"
        if grep -Eq '^Inst (libc6|libsystemd0|systemd|xserver-common|xserver-xorg-core)(:|[[:space:]])' \
            <<<"$apt_plan"; then
            printf '%s\n' "$apt_plan" >&2
            die "The dependency plan would upgrade protected firmware packages."
        fi
        log "Installing only missing runtime packages: ${missing_packages[*]}"
        "${apt_command[@]}" install -y --no-install-recommends "${missing_packages[@]}"
    else
        log "Required Debian runtime packages are already installed."
    fi

    if systemctl list-unit-files NetworkManager.service --no-legend >/dev/null 2>&1; then
        systemctl enable --now NetworkManager.service ||
            die "NetworkManager is installed but could not be started."
    else
        die "NetworkManager.service is unavailable; Wi-Fi support cannot be enabled."
    fi

    installed_common="$(dpkg-query -W -f='${Version}' xserver-common 2>/dev/null || true)"
    [[ "$installed_common" == "$XVFB_VERSION" ]] ||
        platform_mismatch \
            "xserver-common is ${installed_common:-missing}; expected ${XVFB_VERSION}."

    installed_xvfb="$(dpkg-query -W -f='${Version}' xvfb 2>/dev/null || true)"
    if [[ "$installed_xvfb" != "$XVFB_VERSION" ]]; then
        download_verified "$XVFB_URL" "${work_dir}/xvfb.deb" "$XVFB_SHA256"
        log "Installing Xvfb ${XVFB_VERSION} without changing held Xorg packages."
        dpkg -i "${work_dir}/xvfb.deb"
    fi
}

install_klipperscreen_source() {
    local archive="${work_dir}/KlipperScreen-${KS_COMMIT}.tar.gz"
    local extracted="${work_dir}/KlipperScreen-${KS_COMMIT}"
    local previous

    if [[ -x "${KS_DIR}/screen.py" &&
          -f "${KS_DIR}/.q2-pinned-commit" &&
          "$(cat "${KS_DIR}/.q2-pinned-commit")" == "$KS_COMMIT" ]]; then
        log "KlipperScreen source ${KS_COMMIT} is already installed."
    else
        download_verified "$KS_ARCHIVE_URL" "$archive" "$KS_ARCHIVE_SHA256"
        tar -xzf "$archive" -C "$work_dir"
        [[ -x "${extracted}/screen.py" ]] ||
            die "KlipperScreen archive did not contain screen.py"

        if [[ -e "$KS_DIR" ]]; then
            previous="${backup_dir}/KlipperScreen.previous"
            [[ ! -e "$previous" ]] ||
                previous="${backup_dir}/KlipperScreen.previous.$(date +%s)"
            mv -- "$KS_DIR" "$previous"
        fi
        mv -- "$extracted" "$KS_DIR"
        printf '%s\n' "$KS_COMMIT" >"${KS_DIR}/.q2-pinned-commit"
        chown -R qidi:qidi "$KS_DIR"
    fi

    # A pinned GitHub archive intentionally has no .git directory. Teach
    # KlipperScreen to report the verified commit marker instead of logging a
    # misleading FileNotFoundError for the absent git executable.
    python3 - "${KS_DIR}/ks_includes/functions.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
marker = "Q2_PINNED_VERSION_FILE"
if marker not in text:
    needle = "def get_software_version():\n"
    replacement = """def get_software_version():
    # Q2_PINNED_VERSION_FILE: downstream archive-version fallback.
    pinned_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), ".q2-pinned-commit")
    if os.path.isfile(pinned_file):
        with open(pinned_file, "r", encoding="utf-8") as version_file:
            return "q2-" + version_file.read().strip()[:12]
"""
    if needle not in text:
        raise SystemExit("Cannot locate get_software_version() for the Q2 patch")
    path.write_text(text.replace(needle, replacement, 1))
PY
    python3 -m py_compile "${KS_DIR}/ks_includes/functions.py"
    chown qidi:qidi "${KS_DIR}/ks_includes/functions.py"

    local css="${KS_DIR}/styles/material-darker/style.css"
    if [[ -f "$css" ]] && ! grep -q 'QIDI Q2 downstream polish' "$css"; then
        cat >>"$css" <<'Q2_THEME'

/* QIDI Q2 downstream polish for the pinned material-darker KlipperScreen theme. */
@define-color color_1 #f4f7f8;
@define-color color_2 #19c3b1;
@define-color color_3 #ff8a3d;
@define-color color_4 #93a4ab;
@define-color color_5 #10171b;
@define-color background-color_2 #172126;
@define-color background-color_3 #2b3b42;
@define-color background-color_4 #1e2c32;
@define-color background-color_5 #245343;
@define-color background-color_6 #075e67;
@define-color background-color_9 #a95123;
@define-color background-color_10 #8e2930;
@define-color border-color_6 #60757d;
@define-color border-color_7 #263940;
* { font-family: Roboto, Sans; }
window, junction, list row, treeview.view { background-color: #10171b; }
button { background-color: #172126; border-color: #263940; border-radius: 0.35em; }
button.color1, button.color2, button.color3, button.color4 {
    background-color: #1e2c32;
    border-color: #263940;
    border-radius: 0.35em;
    padding-top: 0.42em;
    padding-bottom: 0.42em;
}
button:active, button:focus, button.color1:focus, button.color2:focus,
button.color3:focus, button.color4:focus {
    background-color: #2b3b42;
    border-color: #19c3b1;
}
button.update, .active image { color: #19c3b1; border-color: #19c3b1; }
button.invalid, .dialog-warning { color: #ff8a3d; border-color: #ff8a3d; }
switch:checked, trough progress, trough highlight { background-color: #245343; }
.active_device, .horizontal_togglebuttons_active { background-color: #075e67; }
.frame-item { border-bottom-color: #263940; border-bottom-width: 1px; }
.message_popup_echo, .message_popup_echo button { background-color: #245343; }
.message_popup_warning, .message_popup_warning button { background-color: #a95123; }
.message_popup_error, .message_popup_error button { background-color: #8e2930; }
Q2_THEME
    fi
}

install_python_environment() {
    if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
        log "Creating KlipperScreen Python environment."
        python3 -m venv --system-site-packages "$VENV_DIR"
    fi

    log "Installing pinned Python dependencies."
    "${VENV_DIR}/bin/python" -m pip install --disable-pip-version-check \
        "pip==25.3" "setuptools==80.10.2" "wheel==0.47.0"
    "${VENV_DIR}/bin/python" -m pip install --disable-pip-version-check \
        "python-mpv==0.5.2" \
        "requests==2.32.5" \
        "jinja2==3.1.6" \
        "psutil==7.1.3" \
        "sdbus==0.14.2" \
        "sdbus_networkmanager==2.0.0" \
        "websocket-client==1.9.0"

    chown -R qidi:qidi "$VENV_DIR"
    runuser -u qidi -- env HOME="$QIDI_HOME" \
        "${VENV_DIR}/bin/python" - <<'PY'
import cairo
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
import jinja2
import mpv
import psutil
import requests
import sdbus
import websocket
print("Python/GTK dependencies: OK")
PY
}

write_bridge_source() {
    base64 --decode <<'BRIDGE_GZIP_BASE64' | gzip --decompress >"${work_dir}/q2-x11-fb-bridge.c"
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
BRIDGE_GZIP_BASE64
}

write_bridge_binary() {
    base64 --decode <<'BRIDGE_BINARY_GZIP_BASE64' | gzip --decompress >"${work_dir}/q2-x11-fb-bridge"
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
BRIDGE_BINARY_GZIP_BASE64
    printf '%s  %s\n' "$BRIDGE_BINARY_SHA256" "${work_dir}/q2-x11-fb-bridge" |
        sha256sum --check --status ||
        die "The embedded ARM64 display bridge failed its SHA-256 check."
}

write_gesture_source() {
    base64 --decode <<'GESTURE_GZIP_BASE64' | gzip --decompress >"${work_dir}/q2-display-gesture.c"
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
GESTURE_GZIP_BASE64
}

write_gesture_binary() {
    base64 --decode <<'GESTURE_BINARY_GZIP_BASE64' | gzip --decompress >"${work_dir}/q2-display-gesture"
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
GESTURE_BINARY_GZIP_BASE64
    printf '%s  %s\n' "$GESTURE_BINARY_SHA256" "${work_dir}/q2-display-gesture" |
        sha256sum --check --status ||
        die "The embedded ARM64 gesture daemon failed its SHA-256 check."
}

write_gesture_binary_v2() {
    base64 --decode <<'GESTURE_BINARY_V2_GZIP_BASE64' | gzip --decompress >"${work_dir}/q2-display-gesture"
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
GESTURE_BINARY_V2_GZIP_BASE64
    printf '%s  %s\n' "$GESTURE_BINARY_SHA256" "${work_dir}/q2-display-gesture" |
        sha256sum --check --status ||
        die "The embedded ARM64 gesture daemon failed its SHA-256 check."
}

write_bridge_source_v2() {
    base64 --decode <<'BRIDGE_V2_GZIP_BASE64' | gzip --decompress >"${work_dir}/q2-x11-fb-bridge.c"
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
BRIDGE_V2_GZIP_BASE64
}

write_bridge_binary_v2() {
    base64 --decode <<'BRIDGE_BINARY_V2_GZIP_BASE64' | gzip --decompress >"${work_dir}/q2-x11-fb-bridge"
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
BRIDGE_BINARY_V2_GZIP_BASE64
    printf '%s  %s\n' "$BRIDGE_BINARY_SHA256" "${work_dir}/q2-x11-fb-bridge" |
        sha256sum --check --status ||
        die "The embedded ARM64 display bridge failed its SHA-256 check."
}

write_splash_asset() {
    base64 --decode <<'SPLASH_GZIP_BASE64' | gzip --decompress >"${work_dir}/klipperscreen-splash.bgra"
H4sIAAAAAAACA+3debxc4/0HcPw0EfzsEUkkIrEnIrIIYos1NAiJEFmIfV9iCy2Nnaqtmy5aVC3daBWlVbrRlda+U2qpKqXr77/nl+8kc82d+5yZuXNv7k3l7fV6v15J5syZM88Z53Oe9ay91uppbQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA6Vb81V0t9e69KB0QZ+i0B0EjmrrLSCqnXcj1Szx4foRNEWa46v0xlMQA5a/VeRe4u4hyOMvZbA6Cy3it7uyaD1YMBKIs2Z/nYNaIt2m8OgNCrp7pvV9aB/eYAiPZQudi1tEEDEPNkinKiz+orm0fUpCi7onKN1/32AOSvnFCuAMgJ5QqAnFBGyhUAOaFcAZATKFcA5IRyBUBOLHobDhmQthg5rGmD1u7Tsq/hm6zX9H7GjNhE/gKwxOTviGEbpIm77dC09Qb1b9nXNltu3vR+Juy8rfwFQP7KXwA+RPm7xtDdU6+JN6e11t209PfDZs9Md991Z9NGjxgqfwGQv3VyYtXRh6WlDn8nrbnBuNLfL7rgvNSR/7bfZkv5C4D8lb/yFwD5K38BkL/yV/4C0E3jn/tX/X1A3zWaZvwzAPLX/CP5C4D8lb8AyF/5K38BkL/yF4AlJX9HjVopTT+kZ9pw/VVKf585ff906y03dbop++wlfwGQvwvtuMsK6fyrl0rDh6/cKfOPiv6be/op8hcA+buY5u+gbQ9LvWfc17R1Nh7bsq8Za5+QTlzjiqYct+Yl8heAJSZ/VxtzaFp22m+b1me9MS37mrL8cemEZT/flKM/crn8BWCJyV/j2gBYEnJiYL/V0uBBq6YBfVcr/X3IOv3S0A0Hd7rBA/vKXwDk72Jq2EaD047bjW3akHU+yPktRg5rej87jBsjfwEw/9f4ZwDkr/yVvwDIX/kLgPyVvwDIX/krfwGQv/IXAPkrf+UvAPJX/gIgf+Wv/AWgi/N39eH7pqUPejEtPeuF+Z5f6LkFZj5b4ZmFnl5gxlMLPZmWKZv+RMlyE2+RvwDI3xp6Trx1Qf52op573S5/AZC/BfoMGd3p2bsgf2+TvwDI3wIrjr+0JTN77HN3WmvdTRcavsDgzRYakfoM3ry1ISMXGlXK8QXGlMQ+5C8A8retfv0HpmWmP96Sv6uOmm38lfwFYBHn7ypbHNOSvctMeyT179evy45/0pTV07lXLd200aPWaNnXajednZZ5/sam9Hj0WvkLQJflb//5PjLl/pb8/d/t5nXp8W8xdqU07eCeTdtw/VU+uI84eq+0wpXHNGXFiw+TvwB0Wf6uMXSPD8ZLzXq+bn+tcpW/AHQ8J3rtfn1L/safu/r4B/RdIw3s13uxIH8B6Ir8jbpuaY2NhfkbdeGuPv6Ojr/qLMZfAbAo83f06JXSQUf2SLOO6JEOOGV4mnLO3mnyOZPSlLN2TTMO7Vky/ZAFDpy9QLmv9YCDFprVM+0/c7k0NcxYYL/pC0w5cIHJ0xbYZcIK8heAJT5/x++8Yjr/6qW6zFFzlpW/ACzx+bvjLit0bf6eLH8BkL+bDls5TZy0fBp/4qy0/Rlz0g5nnJx2PWqXtNfkXmnvKQtM2m++qb3SPmH/XmnfcMByJeV25XI7c7ndudwOHW3S0TYdbdTRVj1h4vLyFwDjr+brvdH4Vms0x7qR3XX88heAJSV/l9/1mpbsrfd8QPkrfwHoeP72HbjBgmf4LszfeOav/JW/ACz6/F1x/CVpmemPpWWnPpj6r9Vb/spfALpo/Y1+/QekNdffutuPX/4CsCTl7+JC/gIgf+Wv/AVA/spfAOSv/JW/AHw4cmLo5lumcXse3u222uNg+QvAEpO/vbefm5Y6/J1u9z+zX5G/ACwx+RtrX642cla3W33ENPkLwBKTv8oVADmBcgVATihXAOSEclWuAMgJ5QrA4pgTfVZfufQ67RdlJ38BKNJvzdUKc4JFI8rcbw+AXj17yMUu0mu5Hn5zAJSsstIKsrGLrDq/rP3mACi3QUe9TD4u+rqvtmcAKq3VexUZvIizN8rYbw2AXD042qLlcOfmbrQ5q/cC0GgWm0fUMTIXAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPvwG9F0jbbv1mLTPXrunQw6ano46fHaaNX3/NG7syNJrygig+/34R/ekt996s5Xrrv1i3ffNOfHYNu8re/ON19LQDQenDQYPSK//6ZVWr73159dLOVDez3777tXm/Y8/9nvnpglbbzEy3XLT19Lrr72a/u8//8r627t/Tb/+5YPp+GOOUGYA3eixRx9pc42+43u31XxP1Kn+9c+/F17jTz/lpNJ2kcG513fdcbuWfR02e2ab1//y1hvOTTvNnjmtdO9SdE5yHv7dr9NuO22v/AD+C/J3yj57pvffe7fwmn72WWe0bCt/u8aVl1/artyt9MofX0zDN1lfOQIsxvk7Yecd0l/ffqvwWn7Buee02l7+Lnp7T5zQdPaW/ejeu/ULAyym+bvNVqNr9it+6tKL2rynkfw9YL990j/+/l4rLzz/jHPToDhXuTKOe5gvXvPZNPe0k9Opc05IV19xWXrt1T8Wnr+JE3ZWngCLWf6O2myT9OLzzxZeuz9z1eXZfTeSv3RMtB9Xl+9zzz6VNhwysM22Q9bpl3750M/r9hsA0P35Gxma26Ys6lhF+24kfwfPz4S9PrpbK+O327rVfrYYNbz1Nnvsmgb26116bZMNBqdTTz4+fe4zV6avf+26dN68j6cpkyZm86fyfqL6M9cdsFbptY3WWyedeNxR6TNXX5FuuvG6dNH589LUyXunjdYf1HCZbjZsw3Tg1H3Thed9onRMl3/y4lI7+7gtR9V8X3x29XFFGUbbcPw59nPjDV9NF194btpz911Kx5wr3698+ZrCz9hu6y2y7/nOt26teWwbr79u6RhOm3Ni+tIXPpduuO7adOnF56cTjj0qjd92q8L35c5dfJ8YG3/wzGml308c7zkfm5vGjNy0zfvjO8bv5eQTjil9bmx7xqknlfZV6xwXzcmKuVhxv/i167+S5p19Ztp/yqS6/d8jhm3U5rzEvUz59djvSccfXZo38PnPXpWOO/rwtMM2W7q+AE3n7/rrrl1YXwrXf/XLNffdSP4eevCMuv2/99z9/TbbRL/nKScdl9772zvZz3j7L38u7Tt3XN+89aY22888cGo68rCD0zt//UvhvJ16c3bimhzX4Fp9rc88/WSasMv47PvPmntqm+2v+NQlhW3Mkccxn6v632POV61M/OE9d5fGPv/iZw+U/vzd276VLrnovOy2g9buky675ML0z3+8X/N73XvPXemjE3Zq8/57f3Bnm22jnJ995sk2/x5j6vfde4+W90Y2vvrKS4Wf+e9//aNUBuv0X7PmeYl8jO9b6/hv+/Y3SvcYuffnzunhh8wqjYd46YXnCvd5x3e/U7o/dJ0B2pO/cd2Na2rRtSXmmdYbs9NZ469y1/A777i9obFF13zu6jbH9a1v3Nxmu7u+/93S9bze/qLelLve77j91umJx//Q0DFFH3fUvar38bEzT2vXuKljjjw03ffDH2Rf+8+//1m6/h971GFNj2+OOtzvH/5tw8cT90Kx5kerc1fjN5TL32g7iPKN9of4Do2876EHf5bGjtos+x2iXhr3To3sJ7I06raN5G/cw737ztt19xn9NnEf61oDNJK/kW25jCqLNTvK7b/dlb/tEW2O9fK3Pcrzm1va0Af2LfW5tnc/kZ/N5m9c++O6HvXWettGjv321w+lyy+7uNRuUK++WK73PvnEo+3+TtHuEOuANJO/URcvageoJ+4Tqr9DtNE3muFl0f6x6cbr1c3f9tC3DjSav/V8v876HF2dv9GW+YdHflfYRhp1kMjIRvM3xl8/8vBv0t/f/1v29RgHHn215f3FvKvcdtE2HPcy9993b7Zu/cxTT7S6j2lP/kb9K96z3qD+pfXC2nP+onyjL7VWG3XUz4vafB/7wyPp+eeeLtx/Zf9ze/I3+k0j+3Jt6iH6QqKtPDfmLMRvqfI7xD1Hbrunnngs3f6dbxaWW/V4wrp9CvPP408euK+wnh3/j7nWAJ2Rv7lrXXfkb6z3dNCMA1rNkSqqs338zNPr5m/UKY8+4pCW7WI8UFG/4ScvvqBlbE6uz/g3v3oobb7pxh+sWzJpYvb6HGO9Gsnf6J88/tgjS+PMoq4d47sq24kbaQvNZWmMp6o+b9FenZvn/adXX27Vvhxt7n98+cVsX3mc+1r5+/5775TmRMX4rTgf0fYbY7Ku/dI12eOMdvTy58a4q7vv/F6b7SJPy30iUVa5z/3sp69sueeJbeMYcscf7eD18je2q+zzjvF1uXKL+zjXGqCz8jfmkpavsd2Vv5XX5JZr4NiR2bUxo75TL3/PPH1Om/1FhkZW5Nrg4/UYh5Prx8zVLWPccq5OVy9/f3DXHXXPY3xeZH4z5/KiC+a12teMafs1XN4xFrl6Pa04X+Xx4kX5e9YZp2S/R7Q9VG8bY8jb3CMM3SC73uakPRfcH8R47urXoo2kesxC/D13j/WJj8+tm7+R8dXHFWWZ2zbaKVxvgM7I33Dz12/otvyNOmDR+K9vf/OWNttHe3Kt/I0xw+U5SNW+eu0Xsm3Upevt+fOy1/lG5/7E+N56+Rt52Oj5jDHD8f3buxZ0zNsq7yP6K6tff+P1P2X7/KPMYv5XrEta3W9alL9xP5MbkxR9BLl2+mlT98l+1xgzV3SPEOe7+rW4/8ntJ5eZlfPqcvkbbeS5fcU4+lz51rtXBeRvrp4X9cKi14uujYs6f793+7cLPzfmklZvH+2CtfL3gR//sHB/MYY2V8eN7Ln5xuuz3/HPb77eRq5tMvKmPB6qKH9jvnJ7z2uMn4pnS0X7atSLaz0vo9ynXe4jz91vxDOTmvl95fI3+o+LxlsXHV+uPGvdRxS1xze6n8rfVy5/K9stKkX9O7e/YRsNcb0BGs7fGFMSc1qjnvm73/yycM5G9Nt1df7GOJyi7xTzS2vVQXL5G2OkivYXfa25/W01ZvP04C9+2uH1l0ePGFqYv1FX7IzzHN89xjfl5t2WRR02ts3NaYo52J2VvzEmLbdt9OV3tCyj3hp9Bh3dz68e+kXN/I01s3PfIeZ2y1+gI/n785/e36qNsNZcji9/8fNdnr/fuOXrhd8pciY3B6e8ZlEuf2v1scaz63PfI8boxNzTjl7ry2N4cvkb7eJFxxXzdKKt+Wc/uT89/eTjpfp1zE+udb6jjhtllzuO8liw3HonsVZHZ+VvUb9FPEOxo2UZ9daRwzfp8H5efumFmvlbNAdgl/Hbyl+g6fyNdSRya/vFmhtF80tjXmlX5m/cHxR9p/Pnnd1m+xinW6v9+dHfP1y4vxgjnBsrXdTXHPOgrrrikw0rl3Uuf1968fnC48q1SRT101aKMcy12m5jzZLcHK9afc4xvju3zkcuf4vWTYvfRe64oowbLcvoK4/2mtzcsWj3bnQ/8cyKWvlbOZ5P/gKLYv3n6rHARc8fjPrX4Io1cRd1/kbGFa15FH3W1dtHHbFW/sY9RPW602VxrS0aY5V79m7MLy1anzLWQ64up1rjr2K9yqJzFznR6DjuSrGOZu59scZyvB7ri+TKZ/txY7P9zJVjvaK+/sD9P2oZM5bL35h7XLTGdO64KueYVa+zXTnHq1LMyW2zXudlF2e3jfuf6EsoKi/5C3R3/oZzP/Gxwja7yIOunH+Ua8eM5+jltq2cw1I0/yjaFKvHVMeYoNyY3FjbsdY802hLzY3LjhyL/UU+RDlXZkIuf2NOa9G5iDpn7rOj7ndw5vPL5VM0Nro8tzfGbeVev/XmG9vsLzI7t22MAy7K35jDXPSdIr+rt3/w5z9p28+68w4t663EWORoH4+cjH6SeD03PzjaBqrXY47MLz+XMebzRptC/K5iXpn8BRan/I0xv7m6RblOuttO23fp+leRaTHnN+ZXxr7ivfXGadda/yqu2zFPKOqqkSG5PCg/QyD2FWPP3nzjtex44vJnRqbn5glX52suf2utnRTnomitqHIbfTyjKNpS41lM0cddtG3M2y3Pv4rvXvS8yVgHZI/ddiytkxxrWeTGGUeelcd05/I33lf0neJ5CkXrbpfn0Eadt+i5IOXcL+qzj3aQ8ni3qPfG86TqPc9a/gKLQ/6G6QdMKbyOx7zL8rV3cVn/Ocbzdub6z9VzcWqtwRzrNObyObeOWHvztzRmadaBHR5rFOadc1ar/R5y0PSm9/XpKz9Vs/+3Vv5GThXNHYq+j+jnKBoHWH1eoo+gqH0g+gjef+/dwvU5K5+FJH+BxSV/Q626VKxJsbjkb7T17jx+m07N3/IaS5VtmPWeb5dTPYelmfwtGi/V3uPIrT1S9GylWmLN5cq1ntqbv2HuaSc39Cyq6mcvxbOFK/czee+PFo5XqKVy7JX8BRa3/I21boueTxD1imjDXZT5G+tG1XsmbaytcOD+k9sce3b9q9deza4zWV3/Klr3Otpsc88VrvWsn+pxWM3mb4yBiuf11Tv+ovk6RWsjRvvsDddd2/C+Yox09XioZvK3NOd6/nkr6kvIrcNcnrtcLcaMFfWXZNfFnHuq8VdAl4g2u0bG2eTk1q6vHOMa1+/qjI62w3geeq21LSrnChXlb4zhiX7IWCehuq4Uz9eN9TRirHHuuHP5G/2AO+0wrtQ/WL1WVOR8jAGK5zvUK5O4fsd6U1EfK3oWTjxzIDKzkbFM7Vl3Kvo1o5+03rMY4j4ixppNnbx3Q/uN/oaYn1V0vxN9x1FnzdWhc2PHL7vkwoY+N+7x4jhzz3go13njWUuVzzvMibWoo1yi7TpXry49K3n+55THblWL31r1e2668brstvEbqW4fj/8HKp+XBfDfoih/W66v869tkSWRX9EGWTS/p17+ll+PMVXRdhn7i7bmZtbOjzm4MXY6xmnFGOnYX9F8qUUhnk8QY53jeU7xrIM4hpgTtPuu47PZ34hYuyPa8mOfMYcpxktH5hetw92ZYm3pOMdzTjy2NLY7jqNo3bVa4j2Rs7HWyBGHHlS6h1M3BWguf9urXv4CAPIXAOQvAMhf+QsA8hcAPixibaZY76NSef3HZsTzBar3F+NqlTUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANBefYaMSstNvCUtPfuVkvhz/Fsj7x00aN20+XaT01Z7Hl8Sf45/a+S966zdNw3ddETafMy4kvhz/JtzAsCSkL1LH/xyWurwd1qJf6uXwZGzW008Lo2bNKeV+Ld6GRw5G5k7aux2rcS/yWAAPuyirludvWXxWq33Rl23OnvL4rVa7426bnX2lsVrzg0AH2bR3lyUv/FarfdGe3NR/sZrNbM7U/etrAM7NwDIX/kLANqfAcD4K+OvAMD8IwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIDu9v/HgboDAPgHAA==
SPLASH_GZIP_BASE64
    printf '%s  %s\n' "$SPLASH_BINARY_SHA256" "${work_dir}/klipperscreen-splash.bgra" |
        sha256sum --check --status ||
        die "The embedded KlipperScreen splash failed its SHA-256 check."
}

write_runtime_files() {
    install -d -m 0755 "$LIBEXEC_DIR"
    install -d -o qidi -g qidi -m 0755 \
        "${QIDI_HOME}/printer_data/config" \
        "${QIDI_HOME}/printer_data/logs"

    write_bridge_source_v2
    write_bridge_binary_v2
    write_splash_asset
    install -m 0755 "${work_dir}/q2-x11-fb-bridge" \
        "${LIBEXEC_DIR}/q2-x11-fb-bridge"
    install -d -m 0755 /usr/local/share/klipperscreen-q2
    install -m 0644 "${work_dir}/q2-x11-fb-bridge.c" \
        /usr/local/share/klipperscreen-q2/q2-x11-fb-bridge.c
    install -m 0644 "${work_dir}/klipperscreen-splash.bgra" \
        /usr/local/share/klipperscreen-q2/klipperscreen-splash.bgra

    write_gesture_source
    write_gesture_binary_v2
    systemctl stop q2-display-gesture.service >/dev/null 2>&1 || true
    install -m 0755 "${work_dir}/q2-display-gesture" \
        "${LIBEXEC_DIR}/q2-display-gesture"
    install -m 0644 "${work_dir}/q2-display-gesture.c" \
        /usr/local/share/klipperscreen-q2/q2-display-gesture.c

    cat >"${work_dir}/start-klipperscreen-q2" <<'STARTER'
#!/bin/bash
set -u

export HOME="/home/qidi"
export DISPLAY=":0"
export XDG_RUNTIME_DIR="/run/klipperscreen-q2"
export GDK_BACKEND="x11"
export GTK_THEME="material-darker"
CAPABILITIES="/run/klipperscreen-q2/capabilities.env"
CONTROLS="/run/klipperscreen-q2/controls.json"
PROBE="/home/qidi/q2-moonraker-features.py"
PROBE_JSON="/run/klipperscreen-q2/capabilities.json"
COMPILER="/home/qidi/q2-capability-config.py"

XVFB="/usr/bin/Xvfb"
BRIDGE="/usr/local/libexec/q2/q2-x11-fb-bridge"
PYTHON="/home/qidi/.KlipperScreen-env/bin/python"
SCREEN="/home/qidi/KlipperScreen/screen.py"
CONFIG="/home/qidi/printer_data/config/KlipperScreen.conf"
LOG="/home/qidi/printer_data/logs/KlipperScreen.log"

xvfb_pid=""
bridge_pid=""
screen_pid=""
stopping=0

cleanup() {
    set +e
    [ -n "$screen_pid" ] && kill "$screen_pid" 2>/dev/null
    [ -n "$bridge_pid" ] && kill "$bridge_pid" 2>/dev/null
    [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null
    wait 2>/dev/null
    rm -f /tmp/.X0-lock
}

stop_cleanly() {
    stopping=1
    cleanup
    exit 0
}

trap stop_cleanly INT TERM HUP
trap cleanup EXIT

cd /home/qidi/KlipperScreen
install -d -m 0700 "$XDG_RUNTIME_DIR"
if ! /usr/bin/python3 "$PROBE" --json >"$PROBE_JSON"; then
    /usr/bin/python3 "$COMPILER" /dev/null "$CAPABILITIES" "$CONTROLS" || true
else
    /usr/bin/python3 "$COMPILER" "$PROBE_JSON" "$CAPABILITIES" "$CONTROLS" || true
fi
# The compiler emits only exact, detected macro gates. Unknown/error states
# remain disabled and are not allowed to reach optional UI integrations.
. "$CAPABILITIES"
export Q2_CONTROLS_MANIFEST="$CONTROLS"
rm -f /tmp/.X0-lock

"$XVFB" "$DISPLAY" -screen 0 480x272x24 -nolisten tcp -noreset &
xvfb_pid=$!

attempt=0
while [ ! -S /tmp/.X11-unix/X0 ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        printf 'Xvfb did not become ready.\n' >&2
        exit 1
    fi
    sleep 0.1
done

Q2_BRIDGE_FPS=20 "$BRIDGE" &
bridge_pid=$!

"$PYTHON" "$SCREEN" --configfile "$CONFIG" --logfile "$LOG" &
screen_pid=$!

wait -n "$xvfb_pid" "$bridge_pid" "$screen_pid"
status=$?

if [ "$stopping" -eq 1 ]; then
    exit 0
fi

printf 'KlipperScreen display component exited unexpectedly (status %s).\n' "$status" >&2
exit 1
STARTER

    cat >"${work_dir}/q2-display-mode" <<'DISPLAY_MODE'
#!/bin/sh
set -eu

QIDI_SERVICE="qidi-client.service"
KS_SERVICE="KlipperScreen.service"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf 'Run as root: sudo q2-display-mode %s\n' "${1:-status}" >&2
        exit 1
    fi
}

service_state() {
    if systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q .; then
        systemctl is-active "$1" 2>/dev/null || true
    else
        printf 'not-installed\n'
    fi
}

show_status() {
    printf 'qidi-client: %s\n' "$(service_state "$QIDI_SERVICE")"
    printf 'KlipperScreen: %s\n' "$(service_state "$KS_SERVICE")"
    printf 'boot UI: '
    if systemctl is-enabled --quiet "$KS_SERVICE" 2>/dev/null; then
        printf 'KlipperScreen\n'
    elif systemctl is-enabled --quiet "$QIDI_SERVICE" 2>/dev/null; then
        printf 'QIDI\n'
    else
        printf 'not configured\n'
    fi
}

start_qidi() {
    systemctl stop "$KS_SERVICE" 2>/dev/null || true
    systemctl reset-failed "$KS_SERVICE" 2>/dev/null || true
    systemctl restart "$QIDI_SERVICE"
    sleep 2
    if ! systemctl is-active --quiet "$QIDI_SERVICE"; then
        printf 'Failed to restore the stock QIDI display service.\n' >&2
        exit 1
    fi
    show_status
}

start_klipperscreen() {
    if ! systemctl cat "$KS_SERVICE" >/dev/null 2>&1; then
        printf '%s is not installed.\n' "$KS_SERVICE" >&2
        exit 1
    fi

    systemctl stop "$QIDI_SERVICE"
    if ! systemctl restart "$KS_SERVICE"; then
        systemctl restart "$QIDI_SERVICE"
        printf 'KlipperScreen failed to start; QIDI UI was restored.\n' >&2
        exit 1
    fi

    sleep 5
    if ! systemctl is-active --quiet "$KS_SERVICE"; then
        systemctl stop "$KS_SERVICE" 2>/dev/null || true
        systemctl restart "$QIDI_SERVICE"
        printf 'KlipperScreen did not remain active; QIDI UI was restored.\n' >&2
        exit 1
    fi
    show_status
}

enable_qidi() {
    systemctl disable "$KS_SERVICE" 2>/dev/null || true
    systemctl enable "$QIDI_SERVICE"
    start_qidi
}

enable_klipperscreen() {
    systemctl disable "$QIDI_SERVICE"
    systemctl enable "$KS_SERVICE"
    start_klipperscreen
}

command="${1:-status}"
case "$command" in
    status)
        show_status
        ;;
    qidi)
        require_root "$command"
        start_qidi
        ;;
    klipperscreen)
        require_root "$command"
        start_klipperscreen
        ;;
    enable-qidi)
        require_root "$command"
        enable_qidi
        ;;
    enable-klipperscreen)
        require_root "$command"
        enable_klipperscreen
        ;;
    *)
        printf 'Usage: q2-display-mode {status|qidi|klipperscreen|enable-qidi|enable-klipperscreen}\n' >&2
        exit 2
        ;;
esac
DISPLAY_MODE

    cat >"${work_dir}/KlipperScreen.conf" <<'KS_CONFIG'
[main]
language: en
theme: material-darker
font_size: large
show_cursor: False
confirm_estop: True
use_dpms: False
screen_blanking: off
screen_blanking_printing: off
default_printer: QIDI Q2

[printer QIDI Q2]
moonraker_host: 127.0.0.1
moonraker_port: 7125
titlebar_items: chamber
z_babystep_values: 0.01, 0.05
extrude_distances: 5, 10, 25, 50
extrude_speeds: 1, 2, 5, 10
move_distances: 0.1, 1, 10, 50
KS_CONFIG

    cat >"${work_dir}/KlipperScreen.service" <<'KS_SERVICE'
[Unit]
Description=KlipperScreen for QIDI Q2
After=moonraker.service network-online.target
Wants=network-online.target
Conflicts=qidi-client.service
OnFailure=q2-display-fallback.service
StartLimitIntervalSec=60
StartLimitBurst=2

[Service]
Type=simple
User=qidi
Group=qidi
SupplementaryGroups=video input
RuntimeDirectory=klipperscreen-q2
RuntimeDirectoryMode=0700
EnvironmentFile=-/etc/default/klipperscreen-q2
ExecStart=/usr/local/libexec/q2/start-klipperscreen-q2
Restart=no
TimeoutStopSec=10
UMask=0022

[Install]
WantedBy=multi-user.target
KS_SERVICE

    cat >"${work_dir}/q2-display-fallback.service" <<'FALLBACK_SERVICE'
[Unit]
Description=Restore stock QIDI display after KlipperScreen failure
After=KlipperScreen.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/q2-display-mode qidi
FALLBACK_SERVICE

    cat >"${work_dir}/q2-display-gesture.service" <<'GESTURE_SERVICE'
[Unit]
Description=QIDI Q2 full-screen swipe display switcher
After=local-fs.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/local/libexec/q2/q2-display-gesture
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
GESTURE_SERVICE

    printf 'Q2_TOUCH_MATRIX="%s"\n' "$TOUCH_MATRIX" \
        >"${work_dir}/klipperscreen-q2.default"

    install -m 0755 "${work_dir}/start-klipperscreen-q2" \
        "${LIBEXEC_DIR}/start-klipperscreen-q2"
    install -m 0755 "${work_dir}/q2-display-mode" \
        /usr/local/sbin/q2-display-mode
    install -m 0644 "${work_dir}/KlipperScreen.service" \
        /etc/systemd/system/KlipperScreen.service
    install -m 0644 "${work_dir}/q2-display-fallback.service" \
        /etc/systemd/system/q2-display-fallback.service
    install -m 0644 "${work_dir}/q2-display-gesture.service" \
        /etc/systemd/system/q2-display-gesture.service
    install -m 0644 "${work_dir}/klipperscreen-q2.default" \
        /etc/default/klipperscreen-q2
    install -o qidi -g qidi -m 0644 "${work_dir}/KlipperScreen.conf" \
        "${QIDI_HOME}/printer_data/config/KlipperScreen.conf"
    install_feature_probe
    install_capability_compiler
}

install_feature_probe() {
    install -d -m 0755 "${QIDI_HOME}"
    cat >"${QIDI_HOME}/q2-moonraker-features.py" <<'FEATURE_PROBE'
#!/usr/bin/env python3
import argparse
import json
import sys
import urllib.request

def request(base_url, path):
    with urllib.request.urlopen(f"{base_url.rstrip('/')}/{path}", timeout=2) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise ValueError("Moonraker returned a non-object response")
    result = payload.get("result")
    if not isinstance(result, dict):
        raise ValueError("Moonraker returned no object result")
    return result

def detect(objects):
    available = set(objects)
    macros = sorted(name.removeprefix("gcode_macro ")
                    for name in available if name.startswith("gcode_macro "))
    return {
        "motion": all(name in available for name in ("toolhead", "gcode")),
        "homing": all(name in available for name in ("toolhead", "gcode")),
        "extrusion": "extruder" in available,
        "temperature": any(
            name == "extruder" or
            (name.startswith("extruder") and name[8:].isdigit())
            for name in available
        ),
        "bed_temperature": "heater_bed" in available,
        "fan": "fan" in available,
        "print_controls": "print_stats" in available,
        "filament_macros": {
            action: macro in macros for action, macro in {
                "load": "LOAD_FILAMENT",
                "unload": "UNLOAD_FILAMENT",
                "purge": "PURGE_FILAMENT",
                "select_tool": "SELECT_TOOL",
            }.items()
        },
        "gcode_macros": macros,
    }

    install_capability_compiler() {
        cat <<'CAPABILITY_COMPILER' | sed 's/^    //' >"${QIDI_HOME}/q2-capability-config.py"
    #!/usr/bin/env python3
    import json
    import os
    import sys
    import tempfile

    CONTROL_MACROS = {
        "load": "LOAD_FILAMENT", "unload": "UNLOAD_FILAMENT",
        "purge": "PURGE_FILAMENT", "select_tool": "SELECT_TOOL",
    }

    def compile_config(payload):
        if not isinstance(payload, dict):
            raise ValueError("feature report must be an object")
        macros = payload.get("filament_macros")
        if not isinstance(macros, dict):
            macros = {}
        return "\n".join([
            "Q2_CAPABILITIES_VALID=1",
            f"Q2_FILAMENT_LOAD={int(macros.get('load') is True)}",
            f"Q2_FILAMENT_UNLOAD={int(macros.get('unload') is True)}",
            f"Q2_FILAMENT_PURGE={int(macros.get('purge') is True)}",
            f"Q2_FILAMENT_SELECT_TOOL={int(macros.get('select_tool') is True)}",
            "",
        ])

    def controls_config(payload):
        if not isinstance(payload, dict):
            raise ValueError("feature report must be an object")
        macros = payload.get("filament_macros")
        if not isinstance(macros, dict):
            macros = {}
        return json.dumps({
            "schema": 1, "fail_closed": True, "controls": [
                {"id": "filament-" + action, "action": action, "macro": macro,
                 "available": macros.get(action) is True}
                for action, macro in CONTROL_MACROS.items()
            ],
        }, sort_keys=True, separators=(",", ":")) + "\n"

    def main():
        source, destination, controls_destination = sys.argv[1], sys.argv[2], sys.argv[3]
        try:
            with open(source, encoding="utf-8") as handle:
                payload = json.load(handle)
                content = compile_config(payload)
                controls = controls_config(payload)
            directory = os.path.dirname(destination)
            fd, temporary = tempfile.mkstemp(prefix=".q2-capabilities.", dir=directory, text=True)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, destination)
            directory = os.path.dirname(controls_destination)
            fd, temporary = tempfile.mkstemp(prefix=".q2-controls.", dir=directory, text=True)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(controls)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, controls_destination)
            return 0
        except (OSError, ValueError, json.JSONDecodeError) as error:
            directory = os.path.dirname(destination)
            os.makedirs(directory, mode=0o700, exist_ok=True)
            fd, temporary = tempfile.mkstemp(prefix=".q2-capabilities.", dir=directory, text=True)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write("Q2_CAPABILITIES_VALID=0\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, destination)
            directory = os.path.dirname(controls_destination)
            os.makedirs(directory, mode=0o700, exist_ok=True)
            fd, temporary = tempfile.mkstemp(prefix=".q2-controls.", dir=directory, text=True)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write('{"schema":1,"fail_closed":true,"controls":[]}\n')
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, controls_destination)
            print(f"capability compilation failed: {error}", file=sys.stderr)
            return 1

    if __name__ == "__main__":
        raise SystemExit(main())
    CAPABILITY_COMPILER
        chmod 0755 "${QIDI_HOME}/q2-capability-config.py"
        chown qidi:qidi "${QIDI_HOME}/q2-capability-config.py"
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:7125")
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args()
    try:
        objects = request(args.url, "printer/objects/list").get("objects")
        if not isinstance(objects, list) or not all(isinstance(item, str) for item in objects):
            raise ValueError("Moonraker returned an invalid object list")
        features = detect(objects)
    except (OSError, ValueError) as error:
        print(f"feature detection failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(features, sort_keys=True) if args.as_json else
          "\n".join(f"{name}: {value}" for name, value in features.items()))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
FEATURE_PROBE
    chmod 0755 "${QIDI_HOME}/q2-moonraker-features.py"
    chown qidi:qidi "${QIDI_HOME}/q2-moonraker-features.py"

    usermod -a -G video,input qidi
    systemctl daemon-reload
}

probe_display_bridge() {
    local display=":98"
    local xvfb_pid

    log "Probing the Xvfb/framebuffer bridge."
    rm -f /tmp/.X98-lock
    /usr/bin/Xvfb "$display" -screen 0 480x272x24 -nolisten tcp -noreset \
        >"${work_dir}/xvfb-probe.log" 2>&1 &
    xvfb_pid=$!

    for _ in {1..50}; do
        [[ -S /tmp/.X11-unix/X98 ]] && break
        sleep 0.1
    done
    if [[ ! -S /tmp/.X11-unix/X98 ]]; then
        kill "$xvfb_pid" >/dev/null 2>&1 || true
        wait "$xvfb_pid" >/dev/null 2>&1 || true
        die "Xvfb probe did not start."
    fi

    if ! runuser -u qidi -- env HOME="$QIDI_HOME" DISPLAY="$display" \
        "${LIBEXEC_DIR}/q2-x11-fb-bridge" --probe; then
        kill "$xvfb_pid" >/dev/null 2>&1 || true
        wait "$xvfb_pid" >/dev/null 2>&1 || true
        die "Display bridge probe failed."
    fi
    kill "$xvfb_pid" >/dev/null 2>&1 || true
    wait "$xvfb_pid" >/dev/null 2>&1 || true
}

activate_result() {
    display_was_switched=1
    # LightDM cannot work on the vendor kernel because /dev/tty0 is absent.
    # Both the stock QIDI client and this integration drive /dev/fb0 directly.
    systemctl disable lightdm.service >/dev/null 2>&1 || true
    systemctl reset-failed lightdm.service >/dev/null 2>&1 || true
    systemctl enable q2-display-gesture.service
    systemctl restart q2-display-gesture.service
    if ((enable_at_boot == 1)); then
        log "Enabling KlipperScreen now and at boot."
        /usr/local/sbin/q2-display-mode enable-klipperscreen
    else
        log "Leaving the stock QIDI UI enabled (--no-enable)."
        /usr/local/sbin/q2-display-mode enable-qidi
    fi
}

verify_runtime() {
    sleep 5
    systemctl is-active --quiet q2-display-gesture.service ||
        die "The display gesture service did not remain active."
    systemctl is-enabled --quiet q2-display-gesture.service ||
        die "The display gesture service was not enabled at boot."

    if ((enable_at_boot == 0)); then
        return
    fi

    systemctl is-active --quiet KlipperScreen.service ||
        die "KlipperScreen did not remain active."
    systemctl is-active --quiet moonraker.service ||
        warn "moonraker.service is not active."

    if ! grep -q "Changing state from 'disconnected' to 'ready'" \
        "${QIDI_HOME}/printer_data/logs/KlipperScreen.log"; then
        warn "KlipperScreen is active, but the Moonraker ready state was not found yet."
    fi
}

show_status() {
    printf 'Q2 KlipperScreen installer: %s\n' "$INSTALLER_VERSION"
    if [[ -f "${STATE_DIR}/installed-version" ]]; then
        printf 'Installed by script: %s\n' "$(cat "${STATE_DIR}/installed-version")"
    else
        printf 'Installed by script: no\n'
    fi
    if [[ -x /usr/local/sbin/q2-display-mode ]]; then
        /usr/local/sbin/q2-display-mode status
    else
        printf 'qidi-client: %s\n' "$(systemctl is-active qidi-client.service 2>/dev/null || true)"
        printf 'KlipperScreen: not-installed\n'
    fi
    printf 'display gestures: %s (%s at boot)\n' \
        "$(systemctl is-active q2-display-gesture.service 2>/dev/null || true)" \
        "$(systemctl is-enabled q2-display-gesture.service 2>/dev/null || true)"
    if [[ -s "${STATE_DIR}/initial-backup" ]]; then
        printf 'Initial backup: %s\n' "$(cat "${STATE_DIR}/initial-backup")"
    fi
}

run_install() {
    verify_platform
    check_print_state
    make_initial_backup

    # Keep a working UI on screen while packages and source are installed.
    if [[ -x /usr/local/sbin/q2-display-mode ]]; then
        /usr/local/sbin/q2-display-mode qidi
    else
        systemctl stop KlipperScreen.service >/dev/null 2>&1 || true
        systemctl restart qidi-client.service
    fi
    display_was_switched=1

    install_system_packages
    install_klipperscreen_source
    install_python_environment
    write_runtime_files
    probe_display_bridge
    activate_result
    verify_runtime

    printf '%s\n' "$INSTALLER_VERSION" >"${STATE_DIR}/installed-version"
    printf '%s\n' "$KS_COMMIT" >"${STATE_DIR}/klipperscreen-commit"
    printf '%s\n' "$TOUCH_MATRIX" >"${STATE_DIR}/touch-matrix"

    log "Installation complete."
    show_status
}

main() {
    parse_arguments "$@"
    require_root

    case "$action" in
        status)
            show_status
            return
            ;;
        stock)
            [[ -x /usr/local/sbin/q2-display-mode ]] ||
                die "q2-display-mode is not installed."
            /usr/local/sbin/q2-display-mode enable-qidi
            return
            ;;
        klipperscreen)
            [[ -x /usr/local/sbin/q2-display-mode ]] ||
                die "KlipperScreen is not installed."
            /usr/local/sbin/q2-display-mode enable-klipperscreen
            return
            ;;
        install)
            ;;
    esac

    work_dir="$(mktemp -d /tmp/q2-klipperscreen.XXXXXX)"
    trap 'on_error "$LINENO"' ERR
    trap cleanup EXIT INT TERM HUP
    run_install
}

main "$@"
