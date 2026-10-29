#!/bin/bash
# Write an appcast.xml for a package built by build-pkg.sh.
#   scripts/make-appcast.sh <pkg> <out appcast.xml> [release notes file]
# Needs SPARKLE_PRIVATE_KEY (the key exported by Sparkle's generate_keys -x)
# in the environment, and Sparkle's sign_update from the SwiftPM artifacts.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
pkg=${1:?pkg path}
out=${2:?appcast output path}
notes=${3:-}
version=$("$root/scripts/version.sh")
sign="$root/app/.build/artifacts/sparkle/Sparkle/bin/sign_update"
url="https://github.com/gamunu/hpcups-macos/releases/download/v$version/$(basename "$pkg")"

[ -n "${SPARKLE_PRIVATE_KEY:-}" ] || { echo "SPARKLE_PRIVATE_KEY is not set" >&2; exit 1; }
[ -x "$sign" ] || { echo "missing $sign, run scripts/build-app.sh first" >&2; exit 1; }

# Prints: sparkle:edSignature="..." length="..."
attrs=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign" --ed-key-file - "$pkg" | grep 'sparkle:edSignature')

desc=""
if [ -n "$notes" ] && [ -s "$notes" ]; then
    body=$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$notes")
    desc="<description><![CDATA[<pre style=\"white-space: pre-wrap\">$body</pre>]]></description>"
fi

cat > "$out" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>hpcups Status</title>
    <item>
      <title>Version $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      $desc
      <enclosure url="$url" sparkle:installationType="package" $attrs type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "wrote $out"
