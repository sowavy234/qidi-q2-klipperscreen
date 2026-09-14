#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="${repo_dir}/install-klipperscreen-q2-on-printer.sh"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/q2-repo-check.XXXXXX")"

cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

check_checksum_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$repo_dir" && sha256sum --check install-klipperscreen-q2-on-printer.sh.sha256)
    else
        (cd "$repo_dir" && shasum -a 256 --check install-klipperscreen-q2-on-printer.sh.sha256)
    fi
}

extract_payload() {
    local marker="$1"
    local output="$2"

    awk -v marker="$marker" '
        index($0, "<<\047" marker "\047") { capture = 1; next }
        $0 == marker { capture = 0 }
        capture { print }
    ' "$installer" | base64 --decode | gzip --decompress >"$output"
}

read_constant() {
    local name="$1"

    sed -n "s/^readonly ${name}=\"\\([0-9a-f]*\\)\"$/\\1/p" "$installer"
}

assert_hash() {
    local file="$1"
    local constant="$2"
    local expected
    local actual

    expected="$(read_constant "$constant")"
    actual="$(hash_file "$file")"
    if [[ -z "$expected" || "$actual" != "$expected" ]]; then
        printf 'Hash mismatch for %s: expected %s, got %s\n' \
            "$file" "${expected:-missing}" "$actual" >&2
        exit 1
    fi
}

printf '%s\n' "Checking shell syntax."
bash -n "$installer"
grep -q 'q2-moonraker-features.py' "$installer"
grep -q 'FEATURE_PROBE' "$installer"
grep -q 'q2-capability-config.py' "$installer"
for script in \
    "${repo_dir}/bin/q2-display-mode" \
    "${repo_dir}/bin/start-klipperscreen-q2" \
    "${repo_dir}/tools/physical-bridge-test.sh" \
    "${repo_dir}/tools/touch-calibration-test.sh"; do
    bash -n "$script"
done
python3 -m py_compile "${repo_dir}/tools/q2-capability-config.py"

printf '%s\n' "Checking installer checksum."
check_checksum_file

printf '%s\n' "Checking embedded bridge."
extract_payload BRIDGE_V2_GZIP_BASE64 "${work_dir}/bridge.c"
extract_payload BRIDGE_BINARY_V2_GZIP_BASE64 "${work_dir}/bridge.arm64"
cmp "${repo_dir}/bridge/q2-x11-fb-bridge.c" "${work_dir}/bridge.c"
assert_hash "${work_dir}/bridge.arm64" BRIDGE_BINARY_SHA256

printf '%s\n' "Checking embedded gesture daemon."
extract_payload GESTURE_GZIP_BASE64 "${work_dir}/gesture.c"
extract_payload GESTURE_BINARY_V2_GZIP_BASE64 "${work_dir}/gesture.arm64"
cmp "${repo_dir}/gesture/q2-display-gesture.c" "${work_dir}/gesture.c"
assert_hash "${work_dir}/gesture.arm64" GESTURE_BINARY_SHA256

printf '%s\n' "Checking embedded splash."
extract_payload SPLASH_GZIP_BASE64 "${work_dir}/splash.bgra"
cmp "${repo_dir}/assets/klipperscreen-splash.bgra" "${work_dir}/splash.bgra"
assert_hash "${work_dir}/splash.bgra" SPLASH_BINARY_SHA256

if git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$repo_dir" diff --check
fi

printf '%s\n' "Repository checks: OK"
