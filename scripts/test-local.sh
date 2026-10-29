#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Gamunu Balagalla

# Offline test: render a text page to CUPS raster with macOS cupsfilter,
# run it through build/hpcups, and check the output looks like PCL3GUI2.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
filter="$root/build/hpcups"
ppd="$root/ppd/HP DeskJet 2300 series.ppd"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[ -x "$filter" ] || { echo "missing $filter, run make first" >&2; exit 1; }

# Render $1 (a text file) to raster, filter it, and leave the PCL in $tmp/out.pcl
# and the filter log in $tmp/hpcups.log.
run_filter() {
    txt=$1
    cupsfilter -p "$ppd" -m application/vnd.cups-raster "$txt" \
        > "$tmp/page.ras" 2> "$tmp/cupsfilter.log" \
        || { cat "$tmp/cupsfilter.log" >&2; echo "FAIL: cupsfilter" >&2; exit 1; }
    [ -s "$tmp/page.ras" ] || { echo "FAIL: empty raster" >&2; exit 1; }

    # argv: job user title copies options
    PPD="$ppd" TMPDIR="$tmp" "$filter" 1 "$USER" "local test" 1 "" \
        < "$tmp/page.ras" > "$tmp/out.pcl" 2> "$tmp/hpcups.log" \
        || { cat "$tmp/hpcups.log" >&2; echo "FAIL: hpcups exit status" >&2; exit 1; }
}

printf 'hpcups-macos local test page\nThe quick brown fox jumps over the lazy dog.\n' > "$tmp/page.txt"
run_filter "$tmp/page.txt"

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

pages=$(grep -c '^PAGE: ' "$tmp/hpcups.log")
[ "$pages" -eq 1 ] || { echo "FAIL: one page expected, filter reported $pages" >&2; exit 1; }

echo "PASS: hpcups produced $size bytes of PCL3GUI2 output"

# Two pages: enough text lines to spill onto a second sheet.
i=1
while [ "$i" -le 120 ]; do
    echo "line $i of the two page test"
    i=$((i + 1))
done > "$tmp/two.txt"
run_filter "$tmp/two.txt"

pages=$(grep -c '^PAGE: ' "$tmp/hpcups.log")
[ "$pages" -eq 2 ] || { echo "FAIL: two pages expected, filter reported $pages" >&2; exit 1; }
head -c 2 "$tmp/out.pcl" | xxd -p | grep -qx '1b45' \
    || { echo "FAIL: two page output does not start with ESC E" >&2; exit 1; }
LC_ALL=C grep -aqF $'\x1b%-12345X' "$tmp/out.pcl" \
    || { echo "FAIL: no UEL sequence in two page output" >&2; exit 1; }

echo "PASS: two page job produced $(wc -c < "$tmp/out.pcl" | tr -d ' ') bytes, $pages pages"
