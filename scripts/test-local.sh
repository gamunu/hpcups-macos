#!/bin/bash
# Offline test: render a text page to CUPS raster with macOS cupsfilter,
# run it through build/hpcups, and check the output looks like PCL3GUI2.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
filter="$root/build/hpcups"
ppd="$root/ppd/HP DeskJet 2300 series.ppd"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[ -x "$filter" ] || { echo "missing $filter, run make first" >&2; exit 1; }

printf 'hpcups-macos local test page\nThe quick brown fox jumps over the lazy dog.\n' > "$tmp/page.txt"

cupsfilter -p "$ppd" -m application/vnd.cups-raster "$tmp/page.txt" \
    > "$tmp/page.ras" 2> "$tmp/cupsfilter.log" \
    || { cat "$tmp/cupsfilter.log" >&2; echo "FAIL: cupsfilter" >&2; exit 1; }
[ -s "$tmp/page.ras" ] || { echo "FAIL: empty raster" >&2; exit 1; }

# argv: job user title copies options
PPD="$ppd" TMPDIR="$tmp" "$filter" 1 "$USER" "local test" 1 "" \
    < "$tmp/page.ras" > "$tmp/out.pcl" 2> "$tmp/hpcups.log" \
    || { cat "$tmp/hpcups.log" >&2; echo "FAIL: hpcups exit status" >&2; exit 1; }

size=$(wc -c < "$tmp/out.pcl" | tr -d ' ')
[ "$size" -gt 0 ] || { echo "FAIL: empty output" >&2; exit 1; }

# Job starts with ESC E, then the PJL universal exit language (ESC % -12345 X).
head -c 2 "$tmp/out.pcl" | xxd -p | grep -qx '1b45' \
    || { echo "FAIL: output does not start with ESC E" >&2; exit 1; }
LC_ALL=C grep -aqF $'\x1b%-12345X' "$tmp/out.pcl" \
    || { echo "FAIL: no UEL sequence in output" >&2; exit 1; }
LC_ALL=C grep -aqF '@PJL ENTER LANGUAGE=PCL3GUI' "$tmp/out.pcl" \
    || { echo "FAIL: no PCL3GUI language switch in output" >&2; exit 1; }
grep -q '^PAGE: ' "$tmp/hpcups.log" \
    || { echo "FAIL: filter did not report a page" >&2; exit 1; }

echo "PASS: hpcups produced $size bytes of PCL3GUI2 output"
