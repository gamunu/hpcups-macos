#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Gamunu Balagalla

# Build one unsigned installer package into build/. Does not install anything.
# It installs the CUPS driver (filter and PPD) and /Applications/hpcups Status.app.
# The version comes from scripts/version.sh (VERSION env, git tag vX.Y.Z, VERSION file).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
version=$("$root/scripts/version.sh")
id=io.github.hpcups-macos
stage="$root/build/pkgroot"
out="$root/build/hpcups-macos-$version.pkg"
app="hpcups Status.app"

[ -x "$root/build/hpcups" ] || make -C "$root"
VERSION=$version "$root/scripts/build-app.sh"

rm -rf "$stage" "$root/build/component.pkg" "$root/build/component.plist"
mkdir -p "$stage/Library/Printers/hpcups-macos/filter" \
         "$stage/Library/Printers/PPDs/Contents/Resources" \
         "$stage/Applications"

install -m 755 "$root/build/hpcups" "$stage/Library/Printers/hpcups-macos/filter/hpcups"
gzip -9 -n -c "$root/ppd/HP DeskJet 2300 series.ppd" \
    > "$stage/Library/Printers/PPDs/Contents/Resources/HP DeskJet 2300 series (hpcups-macos).ppd.gz"
chmod 644 "$stage/Library/Printers/PPDs/Contents/Resources/"*.ppd.gz
cp "$root/COPYING" "$root/LICENSE" "$root/LICENSING.md" "$stage/Library/Printers/hpcups-macos/"
ditto --norsrc "$root/build/$app" "$stage/Applications/$app"

xattr -cr "$stage"
export COPYFILE_DISABLE=1

# Keep the app at /Applications. Without this, Installer updates any copy of
# the bundle it finds elsewhere on the disk.
pkgbuild --analyze --root "$stage" "$root/build/component.plist" >/dev/null
# Only the top-level bundle (index 0) needs the flag.
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$root/build/component.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$root/build/component.plist"

# --ownership recommended makes the installer set root:wheel on install.
pkgbuild --root "$stage" \
         --component-plist "$root/build/component.plist" \
         --identifier "$id" \
         --version "$version" \
         --ownership recommended \
         --install-location / \
         "$root/build/component.pkg"

# The distribution file gives the Installer a title and a license pane.
res="$root/build/pkgres"
rm -rf "$res"
mkdir -p "$res"
cp "$root/LICENSE" "$res/LICENSE.txt"
cat > "$root/build/distribution.xml" <<DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>hpcups-macos $version</title>
    <license file="LICENSE.txt" mime-type="text/plain"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <choices-outline>
        <line choice="default"/>
    </choices-outline>
    <choice id="default" title="hpcups-macos (AGPL-3.0-or-later)">
        <pkg-ref id="$id"/>
    </choice>
    <pkg-ref id="$id" version="$version">component.pkg</pkg-ref>
</installer-gui-script>
DIST
productbuild --distribution "$root/build/distribution.xml" \
             --resources "$res" \
             --package-path "$root/build" \
             "$out"
rm -rf "$root/build/component.pkg" "$root/build/component.plist" "$root/build/distribution.xml" "$res"
echo "built $out"
