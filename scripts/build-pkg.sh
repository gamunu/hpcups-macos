#!/bin/bash
# Build an unsigned installer package into build/. Does not install anything.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
version=${VERSION:-3.25.2.1}
id=io.github.hpcups-macos
stage="$root/build/pkgroot"
out="$root/build/hpcups-macos-$version.pkg"

[ -x "$root/build/hpcups" ] || make -C "$root"

rm -rf "$stage" "$root/build/component.pkg"
mkdir -p "$stage/Library/Printers/hpcups-macos/filter" \
         "$stage/Library/Printers/PPDs/Contents/Resources"

install -m 755 "$root/build/hpcups" "$stage/Library/Printers/hpcups-macos/filter/hpcups"
gzip -9 -n -c "$root/ppd/HP DeskJet 2300 series.ppd" \
    > "$stage/Library/Printers/PPDs/Contents/Resources/HP DeskJet 2300 series (hpcups-macos).ppd.gz"
chmod 644 "$stage/Library/Printers/PPDs/Contents/Resources/"*.ppd.gz
cp "$root/COPYING" "$stage/Library/Printers/hpcups-macos/COPYING"

xattr -cr "$stage"
export COPYFILE_DISABLE=1

# --ownership recommended makes the installer set root:wheel on install.
pkgbuild --root "$stage" \
         --identifier "$id" \
         --version "$version" \
         --ownership recommended \
         --install-location / \
         "$root/build/component.pkg"

productbuild --package "$root/build/component.pkg" "$out"
rm -f "$root/build/component.pkg"
echo "built $out"
