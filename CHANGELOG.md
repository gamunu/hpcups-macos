# Changelog

## [0.2.0](https://github.com/gamunu/smudge/compare/v0.1.0...v0.2.0) (2026-10-29)


### ⚠ BREAKING CHANGES

* the old app, filter path, PPDs and receipt are not removed. Uninstall hpcups-macos first and add the printer queue again with the ", Smudge" driver.

### Features

* install from terminal without the gatekeeper prompt ([0bee356](https://github.com/gamunu/smudge/commit/0bee35619b57bf7d2e51675bc232b0c99fc5ac2f))
* rename the project and app to smudge ([26c824d](https://github.com/gamunu/smudge/commit/26c824d7cace95b36c2725f8ec437bcf7e4629da))


### Documentation

* **readme:** add the homebrew install ([baefbb6](https://github.com/gamunu/smudge/commit/baefbb6687861870c094942f747b915770397110))

## 0.1.0 (2026-10-29)

First release.

- Native Apple Silicon build of HPLIP's hpcups driver, with PPDs for 778 HP printers that work without HP's plugin.
- hpcups Status: printer state, jobs, ink levels, and guided cleaning, diagnostics and head alignment with pictures for every step.
- One installer for the driver and the app, and automatic updates with Sparkle.

Tested on hardware: HP DeskJet 2300 over USB.
