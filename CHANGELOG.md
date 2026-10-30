# Changelog

## [0.3.0](https://github.com/gamunu/smudge/compare/v0.2.0...v0.3.0) (2026-10-30)


### Features

* **firmware:** load HP firmware into LaserJets at power-on ([6d9f865](https://github.com/gamunu/smudge/commit/6d9f86578ea73e64c4c69418fd09a8456004dff1))
* **jpeg:** port the JetReady Mojave color table, enable JetReady and QuickConnect ([4312a5d](https://github.com/gamunu/smudge/commit/4312a5d56a997f3a2d62d3adcd0366594f453ec8))
* **ppd:** keep models whose plugin need is scan or speed only ([03cbebb](https://github.com/gamunu/smudge/commit/03cbebb0ef7fd30a00384bacea55cbc787926edb))
* print on the HP printers that needed HP's plugin ([80aaf99](https://github.com/gamunu/smudge/commit/80aaf9980b8e58e226a7ebdf7b35eeb2198149fd))
* **zjs:** compress ZjStream and ZxStream pages without HP's plugin ([fb98df2](https://github.com/gamunu/smudge/commit/fb98df2ff28debbc972c0bcf9996b554c615d153))

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
