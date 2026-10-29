# hpcups-macos

The `hpcups` CUPS filter from HPLIP 3.25.2, built natively for macOS (arm64),
with a PPD and an installer package for the HP DeskJet 2300 series over USB.

HP does not ship a macOS driver for this printer that works on current macOS.
This project builds HPLIP's open-source raster filter and installs it where
the macOS print system can use it. No HP binary plugin is needed for this
model.

## Supported printers

- HP DeskJet 2300 series (also sold as DeskJet Ink Advantage 2300)

Other HP models that use `*hpPrinterLanguage: "pcl3gui2"` in their HPLIP PPD
may work with a modified PPD. Only the 2300 series has been prepared here.

## What is different from upstream

- Built without HP's prebuilt image processor library (`DISABLE_IMAGEPROCESSOR`).
- Built without dbus status reporting.
- libjpeg is linked statically, so the filter only depends on system libraries.
- Small portability changes are listed in `src/hpcups/UPSTREAM`.
- The JetReady and QuickConnect JPEG colour table tweak is not built. The
  2300 series does not use it.

## Build

Requires Xcode command line tools and a static libjpeg
(`brew install jpeg-turbo pkgconf`).

    make

This writes `build/hpcups`. The result links only against `/usr/lib`:

    otool -L build/hpcups

Use `make JPEG_PREFIX=/path/to/jpeg` if libjpeg is somewhere else.

## Test without a printer

    make test

This renders a text page to CUPS raster with `cupsfilter`, runs it through
`build/hpcups` and checks that PCL3GUI2 output comes out.

## Install

Download `hpcups-macos-<version>.pkg` from the
[Releases](https://github.com/gamunu/hpcups-macos/releases/latest) page.

The package is not signed with an Apple Developer ID, so macOS blocks a
double click. Right click the file in Finder, choose Open, then Open again.
If it still refuses, System Settings > Privacy & Security shows an
"Open Anyway" button for it. From a shell:

    sudo installer -pkg hpcups-macos-<version>.pkg -target /

One package installs everything:

- `/Library/Printers/hpcups-macos/filter/hpcups`
- `/Library/Printers/PPDs/Contents/Resources/HP DeskJet 2300 series (hpcups-macos).ppd.gz`
- `/Applications/hpcups Status.app`

The installer does not add a printer. Do that in the next section.

To build the package yourself:

    make pkg

This writes `build/hpcups-macos-<version>.pkg`. The version is the tag
(`vX.Y.Z`) when HEAD is tagged, otherwise the `VERSION` file, otherwise
`0.0.0-dev`. `VERSION=1.2.3 make pkg` overrides it.

## Add the printer

Connect the printer by USB, then either use System Settings > Printers & Scanners
and pick "HP DeskJet 2300 series, hpcups-macos" as the driver, or from a shell:

    lpinfo -v | grep -i usb
    sudo lpadmin -p HP_DeskJet_2300 -E -v "<usb uri from lpinfo>" \
        -P "/Library/Printers/PPDs/Contents/Resources/HP DeskJet 2300 series (hpcups-macos).ppd.gz"

Print a test page:

    lp -d HP_DeskJet_2300 /etc/hosts

If a job fails, `log show --last 5m --predicate 'process == "hpcups"'` and
`/var/log/cups/error_log` show the filter messages.

## Status app

`hpcups Status` is a normal Mac app (SwiftUI, no Xcode project) with a Dock
icon, a main window and a menu bar item. It talks to CUPS through libcups,
not `lpstat`.

The window has a sidebar with five sections:

- Overview: printer name and model, a state card (Ready, Printing, Needs
  attention, Disconnected) with the reasons in plain words, USB status, ink
  summary, the current job and quick actions.
- Jobs: a table of active and past jobs (title, state, size, submitted time),
  cancel selected, cancel all, pause or resume the queue.
- Ink: one cartridge picture each for black and tri-color, level, state,
  cartridge number and last read time. See "Ink levels" below.
- Maintenance: guided flows for clean, deep clean, diagnostics page and
  alignment. See "Maintenance" below.
- Settings: notifications, ink refresh interval, queue polling interval and
  "Show in menu bar".

The menu bar popover is a short status view: state, ink bars, the active job
and an "Open hpcups Status" button. Closing the window keeps the menu bar item
running. Queues whose PPD make-and-model contains "hpcups-macos" are listed
(all queues if none match). Reasons starting with `com.hp.` are shown raw as
"Driver reported". The app sends a notification when a job completes or fails
and when ink gets low. The first launch asks for notification permission.

Build:

    scripts/build-app.sh

This runs `swift build -c release` in `app/` and writes
`build/hpcups Status.app` with Sparkle embedded, ad-hoc signed. Run it with:

    open "build/hpcups Status.app"

`--open-section overview|jobs|ink|maintenance|settings` picks the section the
window starts in. For a text check without the GUI:

    "build/hpcups Status.app/Contents/MacOS/hpcups Status" --dump

## Ink levels

The app reads ink levels from the printer itself. It shows one bar for the
black cartridge and one for the tri-color cartridge, the percentage the
printer reports, and a state: OK, Low, Very low, Empty, Missing, or Non-HP or
refilled. Levels refresh when the popover opens and every 60 seconds. If the
printer does not report a percentage the app shows "unknown". It never
estimates. You get one notification when a cartridge changes to low, very
low, empty or missing.

`--dump` prints the parsed ink data and the supported maintenance job types.
`--ledm-get <path>` prints the raw reply for one printer resource, for
debugging:

    "build/hpcups Status.app/Contents/MacOS/hpcups Status" --ledm-get /DevMgmt/ConsumableConfigDyn.xml

If the printer is not reachable the Ink section shows the reason. If CUPS
reports `marker-levels` and the printer read fails, those values are shown.

## Maintenance

The Maintenance section has four guided flows:

- Clean print heads (`cleaningPage`)
- Deep clean (`cleaningPageLevel2`)
- Print diagnostics page (`diagnosticsPage`)
- Align print heads (calibration session, semi-automatic)

Each flow opens a sheet with steps, and polls the printer every 2 seconds
(`/DevMgmt/ProductStatusDyn.xml`) to show what it is doing. If the printer
reports an empty or open paper tray the sheet says "Load paper", and for an
open door it says "Close the door". The job continues by itself once that is
fixed. All flows use ink and paper, and deep clean uses the most ink. The
actions are disabled, with the reason shown, while a print job is active or
the USB device is not found.

Every running step has a Cancel button. It stops the flow and sends a cancel
to each active printer job (`PUT /Jobs/JobList/<n>` with JobState Canceled).
The Overview card and the menu bar show "Cancel alignment" while the printer
reports calibrating. `--maint cancel` does the same from the command line and
`--ledm-jobs` lists the printer's own job list.

Clean and deep clean print no page on the DeskJet 2300. The flow is done when
the printer goes from processing back to ready, and it offers to print the
diagnostics page to check. The diagnostics flow ends with guidance on reading
the page.

Alignment on this printer goes through `/Calibration/State` like this:
CalibrationRequired, then Printing (status calibrating), then ScanRequested
(the page is out; place it printed side down on the scanner glass, top edge to
the back, in the marker corner, close the lid, press Color Copy once), then
Scanning, then back to CalibrationRequired with status ready after about 15
seconds. The printer does not report CalibrationValid after a good alignment.
The app counts the alignment as done when the state passed through Scanning
and the printer is ready with nothing to fix. CalibrationValid also counts. If
the printer returns to ready without ever scanning, the app says the scan was
not detected. If the printer's Attention light is blinking afterwards, the
alignment failed; reload the page and try again.

## How it talks to the printer

The printer exposes an HTTP server (LEDM, the "embedded web server") on a
vendor USB interface (class 255, subclass 4, protocol 1). HPLIP uses the same
interface on Linux. The app claims that interface through IOUSBHost and sends
HTTP requests over its bulk endpoints. There is no libusb or Homebrew
dependency. CUPS keeps using the separate printing interface, so printing is
not affected.

Replies from this printer are slow and sometimes arrive late. The client
sends one request at a time, discards leftover bytes before each request,
reads until the HTTP reply is complete (Content-Length or the last chunk), and
checks that the XML root matches the resource it asked for. A reply that does
not match is dropped and the client keeps reading. Request formats for the
maintenance jobs are copied from HPLIP 3.25.2 (`base/maint.py`,
`base/device.py`).

## Updates

The app checks for updates with Sparkle, once a day by default. "Check for
Updates..." is in the app menu and in Settings, which also has the automatic
check toggle and the time of the last check.

An update is the same `.pkg` as a fresh install, so the driver and the app are
updated together. Sparkle verifies the package with an EdDSA signature and
then opens it in Installer. Because the package is unsigned, that signature is
the only check, and the public key is baked into the app.

Builds made without `SPARKLE_PUBLIC_KEY` cannot verify updates and will refuse
them.

## Releasing

Tag the version and push the tag:

    git tag -a v1.2.3 -m "Release notes go here"
    git push origin v1.2.3

The `release` workflow builds the package, signs it for Sparkle, writes
`appcast.xml` and creates a GitHub Release with both attached. The tag message
is the release text. A lightweight tag falls back to the commit subjects since
the previous tag. Tags with a `-` (for example `v1.2.3-rc1`) are marked as
pre-releases and are not offered to installed apps.

The `ci` workflow builds and tests every push and pull request and uploads the
package as an artifact.

## One-time setup for maintainers

Without these, releases still build, but there is no `appcast.xml` and the app
cannot verify updates.

1. Get Sparkle's tools. Build the app once, then use the copy SwiftPM fetched:

        scripts/build-app.sh
        BIN="$PWD/app/.build/artifacts/sparkle/Sparkle/bin"

2. Generate the key pair. The private key goes into your login keychain and
   the command prints the public key:

        "$BIN/generate_keys"

3. Export the private key to a file, store it as a repository secret, then
   delete the file:

        "$BIN/generate_keys" -x /tmp/sparkle_private_key
        gh secret set SPARKLE_PRIVATE_KEY --repo gamunu/hpcups-macos < /tmp/sparkle_private_key
        rm /tmp/sparkle_private_key

4. Store the public key as a repository variable:

        gh variable set SPARKLE_PUBLIC_KEY --repo gamunu/hpcups-macos --body "$("$BIN/generate_keys" -p)"

Keep a backup of the private key in a password manager. If it is lost, every
installed copy of the app needs a manual reinstall, because it only accepts
updates signed with the matching key.

## Uninstall

Remove the printer queue first, then run the uninstall script from this
repository:

    sudo lpadmin -x HP_DeskJet_2300
    sudo scripts/uninstall.sh

It removes the app, the filter, the PPD and the installer receipt.

## License

hpcups-macos is licensed under AGPL-3.0-or-later. See `LICENSE`.

HP's code in `src/hpcups/` and `src/common/` keeps its original headers
(BSD-style, GPL-2.0-or-later, or none) and is not relicensed. HPLIP's own
license text is in `COPYING`. `LICENSING.md` lists which files carry which
license and why the combined driver is AGPL-3.0-or-later.

Source files written for this project start with an SPDX line.
`scripts/check-spdx.sh` checks that, and CI runs it.
