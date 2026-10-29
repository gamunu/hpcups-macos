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

## Uninstall

    sudo lpadmin -x HP_DeskJet_2300
    sudo rm -rf /Library/Printers/hpcups-macos
    sudo rm "/Library/Printers/PPDs/Contents/Resources/HP DeskJet 2300 series (hpcups-macos).ppd.gz"
    sudo pkgutil --forget io.github.hpcups-macos

## License

See `LICENSE`. HPLIP sources keep their original headers (GPL v2, MIT, BSD).
