# Licensing

hpcups-macos as a whole is distributed under the GNU Affero General Public
License, version 3 or (at your option) any later version
(AGPL-3.0-or-later). The full text is in `LICENSE`.

The project mixes two kinds of files, and each keeps its own license notice.

## Files written for this project

These carry `SPDX-License-Identifier: AGPL-3.0-or-later` and
`Copyright (C) 2026 Gamunu Balagalla` at the top:

- `app/` (the hpcups Status app, its tests and `Package.swift`)
- `scripts/`
- `Makefile`
- `src/compat/`
- `.github/`

`scripts/check-spdx.sh` fails the CI build when one of these files has no
SPDX line.

## Files taken from HPLIP

`src/hpcups/` and `src/common/` come from HPLIP 3.25.2 (see
`src/hpcups/UPSTREAM`). They keep the headers and copyrights HP put on
them. We did not relicense or restamp them. HPLIP is distributed under a
mix of licenses, and the header of each file says which one applies:

- most of the filter sources carry a BSD-style notice,
- a few carry the GNU GPL, version 2 or (at your option) any later version,
- some data tables and headers have no header at all and are covered by the
  terms HP gives for the HPLIP tarball in `COPYING`.

`COPYING` is HP's text, unchanged.

The PPD in `ppd/` is derived from HP's PPD for the DeskJet 2300 series and
keeps HP's copyright line.

## Why the combined driver is AGPL-3.0-or-later

BSD-style and MIT notices allow redistribution under other terms as long
as the notice stays. GPL-2.0-or-later lets the recipient pick version 3 or
any later version, and the AGPL-3.0 is written to combine with GPL-3.0
code (section 13 of each license). The files that have no header are
distributed with the rest of HPLIP under `COPYING`, which is the same mix.
So the `hpcups` binary, which links all of these together, can be
distributed as a whole under AGPL-3.0-or-later. Each HP file stays under
its own notice for anyone who takes it out of this tree.

The installer package ships `LICENSE`, `LICENSING.md` and `COPYING` under
`/Library/Printers/hpcups-macos/`. The source is at
https://github.com/gamunu/hpcups-macos.

## Binaries and libraries

The filter links libjpeg-turbo statically (IJG and BSD-3-Clause licenses;
its notices are in its own `LICENSE.md` and `README.ijg`). The app embeds
the Sparkle framework (MIT license, with notices for its bundled
components in the Sparkle repository).
