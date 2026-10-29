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

Build and install the package:

    scripts/build-pkg.sh
    sudo installer -pkg build/hpcups-macos-*.pkg -target /

The package is unsigned. Open it from Finder with right click and Open if
Gatekeeper blocks it, or use `installer` as above.

It installs:

- `/Library/Printers/hpcups-macos/filter/hpcups`
- `/Library/Printers/PPDs/Contents/Resources/HP DeskJet 2300 series (hpcups-macos).ppd.gz`

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

`hpcups Status` is a small menu bar app (SwiftUI, no Xcode project) for the
queue. It talks to CUPS through libcups, not `lpstat`.

- Lists queues whose PPD make-and-model contains "hpcups-macos" (all queues
  if none match). `HP_DeskJet_2300` is the default.
- Shows the printer state, the state message and the state reasons in plain
  words, for example "Out of paper" or "Printer offline or unplugged".
  Reasons starting with `com.hp.` are shown raw as "Driver reported".
- Checks that the USB device is connected by matching the serial in the
  queue's device URI against the USB registry.
- Shows ink levels read from the printer (see "Ink levels" below).
- Has maintenance actions: clean, deep clean, diagnostics page, alignment
  (see "Maintenance" below).
- Lists active and recent jobs with a cancel button, plus cancel all,
  pause or resume the printer, and a test page.
- The menu bar icon changes when the printer is processing, and shows a
  warning when it is stopped, offline or reports an error.
- Polls every 3 seconds and sends a notification when a job completes or
  fails. It asks for notification permission on first launch.

Build:

    scripts/build-app.sh

This runs `swift build -c release` in `app/` and writes
`build/hpcups Status.app`, ad-hoc signed. Run it with:

    open "build/hpcups Status.app"

The app has no Dock icon. Look for the printer icon in the menu bar. Quit
from the Quit button in the popover.

For a text check without the GUI:

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

The Maintenance section has four actions:

- Clean print heads (`cleaningPage`)
- Deep clean (`cleaningPageLevel2`)
- Print diagnostics page (`diagnosticsPage`)
- Align print heads (calibration session, semi-automatic)

Each one asks for confirmation first. All of them use ink and paper, and deep
clean uses the most ink. Load plain paper before you start. The buttons are
disabled while a print job is active, while the printer is processing, or when
the USB device is not found.

For alignment the printer prints a page. Put it face down on the scanner glass
and press the Enter or Scan button on the printer. The app watches the
printer's calibration state and shows the result.

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

## Uninstall

    sudo lpadmin -x HP_DeskJet_2300
    sudo rm -rf /Library/Printers/hpcups-macos
    sudo rm "/Library/Printers/PPDs/Contents/Resources/HP DeskJet 2300 series (hpcups-macos).ppd.gz"
    sudo pkgutil --forget io.github.hpcups-macos

## License

See `LICENSE`. HPLIP sources keep their original headers (GPL v2, MIT, BSD).
