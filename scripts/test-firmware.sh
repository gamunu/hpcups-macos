#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Gamunu Balagalla

# Offline test of the firmware loader, no printer needed.
#  1. The device-ID rule: FWVER in the 1284 ID means firmware is running.
#  2. Model name to firmware file mapping.
#  3. The loader's dry run and a real run against a fake usb backend.
#  4. With SMUDGE_TEST_NETWORK=1, the fetch script against HP's real plugin.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
loader="$root/scripts/smudge-firmware-load"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# ---- 1 and 2. functions ----
fw="$tmp/fw"
mkdir "$fw"
for m in hp_laserjet_1018 hp_laserjet_1005_series hp_laserjet_p1006 hp_laserjet_p1505 \
         hp_laserjet_professional_p1566; do
    printf 'FIRMWARE-%s' "$m" | gzip -c > "$fw/$m.fw.gz"
done

# shellcheck disable=SC1090
SMUDGE_FW_SOURCE_ONLY=1 SMUDGE_FIRMWARE_DIR="$fw" . "$loader"

fw_loaded 'MFG:Hewlett-Packard;MDL:HP LaserJet P1006;CMD:ACL;FWVER:20080415;' \
    || fail "FWVER in the ID must count as loaded"
fw_loaded 'MFG:Hewlett-Packard;MDL:HP LaserJet P1006;CMD:ACL;CLS:PRINTER;' \
    && fail "an ID without FWVER must count as not loaded"
fw_loaded '' && fail "an empty ID must count as not loaded"

[ "$(id_model 'MFG:HP;MDL:HP LaserJet 1018;CMD:ACL;')" = "HP LaserJet 1018" ] || fail "id_model MDL"
[ "$(id_model 'MFG:HP;MODEL:HP LaserJet 1018;')" = "HP LaserJet 1018" ] || fail "id_model MODEL"
[ -z "$(id_model 'MFG:HP;CMD:ACL;')" ] || fail "id_model with no model"

check_file() { # model expected-stem
    got=$(fw_file "$1" || true)
    [ "$got" = "$fw/$2.fw.gz" ] || fail "fw_file '$1': got '$got', want $2"
}
check_file "HP LaserJet 1018" hp_laserjet_1018
check_file "HP LaserJet 1005" hp_laserjet_1005_series
check_file "HP LaserJet P1006" hp_laserjet_p1006
check_file "HP LaserJet P1505n" hp_laserjet_p1505
check_file "LaserJet P1006" hp_laserjet_p1006
check_file "HP LaserJet Professional P1566" hp_laserjet_professional_p1566
[ -z "$(fw_file 'HP DeskJet 2300 series' || true)" ] || fail "DeskJet must have no firmware"
[ -z "$(fw_file 'HP LaserJet Professional P1567' || true)" ] || fail "P1567 has no firmware file"
echo "PASS: device-ID rule and firmware file mapping"

# ---- 3. loader runs ----
cat > "$tmp/list" <<'EOF'
direct usb://HP/LaserJet%20P1006?serial=AAA "HP LaserJet P1006" "HP LaserJet P1006" "MFG:Hewlett-Packard;MDL:HP LaserJet P1006;CMD:ACL;CLS:PRINTER;" ""
direct usb://HP/LaserJet%201018?serial=BBB "HP LaserJet 1018" "HP LaserJet 1018" "MFG:Hewlett-Packard;MDL:HP LaserJet 1018;CMD:ACL;FWVER:20080415;CLS:PRINTER;" ""
direct usb://HP/DeskJet%202300%20series?serial=CCC "HP DeskJet 2300 series" "HP DeskJet 2300 series" "MFG:HP;MDL:DeskJet 2300 series;CMD:LDL,PCL;" ""
direct usb://HP/LaserJet%20P1505n?serial=DDD "HP LaserJet P1505n" "HP LaserJet P1505n" "MFG:Hewlett-Packard;MDL:HP LaserJet P1505n;CMD:ACL;" ""
direct usb://HP/LaserJet%201005?serial=EEE "HP LaserJet 1005" "HP LaserJet 1005" "MFG:Hewlett-Packard;MDL:HP LaserJet 1005;CMD:ACL;" ""
network socket://printer.local "Network Printer" "Network" "" ""
EOF

out=$(SMUDGE_FW_LOCK="$tmp/lock" SMUDGE_FIRMWARE_DIR="$fw" SMUDGE_DEVICE_LIST="$tmp/list" \
    SMUDGE_DRY_RUN=1 "$loader" 2>&1)
echo "$out" | grep -q "dry run: would send $fw/hp_laserjet_p1006.fw.gz to usb://HP/LaserJet%20P1006?serial=AAA" \
    || fail "dry run missed the P1006"
echo "$out" | grep -q "dry run: would send $fw/hp_laserjet_p1505.fw.gz to usb://HP/LaserJet%20P1505n" \
    || fail "dry run missed the P1505n"
echo "$out" | grep -q "dry run: would send $fw/hp_laserjet_1005_series.fw.gz to usb://HP/LaserJet%201005" \
    || fail "dry run missed the 1005"
echo "$out" | grep -q "HP LaserJet 1018: firmware already running" || fail "1018 with FWVER must be skipped"
[ "$(echo "$out" | grep -c 'would send')" = 3 ] || fail "dry run sent to the wrong number of devices"
[ ! -e "$tmp/lock" ] || fail "lock was left behind"

# A fake backend records the device URI and the bytes it is handed.
cat > "$tmp/backend" <<'EOF'
#!/bin/sh
[ $# -eq 5 ] || [ $# -eq 6 ] || exit 2
echo "$DEVICE_URI $(cat)" >> "$SMUDGE_TEST_LOG"
EOF
chmod +x "$tmp/backend"
SMUDGE_TEST_LOG="$tmp/sent" SMUDGE_USB_BACKEND="$tmp/backend" SMUDGE_FW_LOCK="$tmp/lock" \
    SMUDGE_FIRMWARE_DIR="$fw" SMUDGE_DEVICE_LIST="$tmp/list" "$loader" 2> /dev/null
grep -qx 'usb://HP/LaserJet%20P1006?serial=AAA FIRMWARE-hp_laserjet_p1006' "$tmp/sent" \
    || fail "firmware bytes did not reach the backend decompressed"
[ "$(wc -l < "$tmp/sent" | tr -d ' ')" = 3 ] || fail "backend got the wrong number of jobs"
echo "PASS: loader dry run and fake backend run"

# No firmware directory content: nothing sent, exit 0.
mkdir "$tmp/empty"
SMUDGE_FW_LOCK="$tmp/lock" SMUDGE_FIRMWARE_DIR="$tmp/empty" SMUDGE_DEVICE_LIST="$tmp/list" \
    SMUDGE_DRY_RUN=1 "$loader" 2>&1 | grep -q "no firmware in" || fail "empty firmware dir not reported"
echo "PASS: loader with no firmware installed"

# ---- 4. the real download ----
if [ -n "${SMUDGE_TEST_NETWORK:-}" ]; then
    mkdir "$tmp/real"
    SMUDGE_FIRMWARE_DIR="$tmp/real" TMPDIR="$tmp" "$root/scripts/fetch-firmware.sh"
    [ -f "$tmp/real/hp_laserjet_p1006.fw.gz" ] || fail "fetch did not produce the P1006 firmware"
    [ "$(find "$tmp/real" -type f ! -name '*.fw.gz' | wc -l | tr -d ' ')" = 0 ] \
        || fail "fetch installed something besides firmware"
    echo "PASS: fetch-firmware.sh against the real plugin"
fi
