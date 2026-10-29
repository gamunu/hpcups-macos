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
`build/hpcups Status.app`, ad-hoc signed. Run it with:

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

## Uninstall

    sudo lpadmin -x HP_DeskJet_2300
    sudo rm -rf /Library/Printers/hpcups-macos
    sudo rm "/Library/Printers/PPDs/Contents/Resources/HP DeskJet 2300 series (hpcups-macos).ppd.gz"
    sudo pkgutil --forget io.github.hpcups-macos

## License

See `LICENSE`. HPLIP sources keep their original headers (GPL v2, MIT, BSD).
