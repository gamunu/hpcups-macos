#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Gamunu Balagalla

"""Pick the HPLIP hpcups PPDs this package can serve and build the install set.

Subcommands:

  select --hplip DIR   Maintainer step. Read DIR/data/models/models.dat and
                       DIR/ppd/hpcups/*.ppd.gz (an HPLIP source tree), decide
                       which PPDs to keep, copy the kept ones to ppd/hplip/ and
                       write ppd/hplip/manifest.tsv, ppd/hplip/excluded.tsv and
                       docs/supported-printers.md.
  build --out DIR      Build step. Rewrite the vendored PPDs for macOS and write
                       them gzipped under DIR (laid out like
                       /Library/Printers/PPDs/Contents/Resources).
  check DIR            Check the PPDs that build wrote (required keywords,
                       filter path, unique names). Exit 1 on any problem.
  docs                 Rewrite docs/supported-printers.md from the manifests.

Selection rules, in order. A PPD is excluded when:
  1. its *cupsFilter is not the hpcups raster filter,
  2. a models.dat entry for one of its products has plugin=1 or plugin=2
     (HP's closed binary plugin is required),
  3. its *hpPrinterLanguage is one we leave out (see LANGUAGES),
  4. no models.dat entry matches any of its products (plugin status unknown).
"""

import argparse
import collections
import glob
import gzip
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(ROOT, "ppd", "hplip")
MANIFEST = os.path.join(VENDOR, "manifest.tsv")
EXCLUDED = os.path.join(VENDOR, "excluded.tsv")
DOC = os.path.join(ROOT, "docs", "supported-printers.md")

STOCK_FILTER = 'application/vnd.cups-raster 0 hpcups'
FILTER_PATH = "/Library/Printers/hpcups-macos/filter/hpcups"
SUBDIR = "hpcups-macos"

# Languages whose encapsulator is compiled into build/hpcups (every
# src/hpcups/*.cpp is built and EncapsulatorFactory.cpp knows all of them).
# value: None when the language is served, else the reason it is left out.
# LJZjStream and LJZxStream always run ModeJbig, which loads the JBIG
# compressor from HP's plugin (lj.so). Without it the filter stops with
# PLUGIN_LIBRARY_MISSING (error 48) before it writes a page, even though
# models.dat says plugin=0 for most of these models.
ZJS = "JBIG compressor is in the HP plugin (filter fails, error 48)"

LANGUAGES = {
    "pcl3": None,
    "pcl3gui": None,
    "pcl3gui2": None,
    "lidil": None,
    "ljmono": None,
    "ljcolor": None,
    "ljzjstream": ZJS,
    "ljzxstream": ZJS,
    "ljfastraster": None,
    "hbpl1": None,
    # The JPEG paths call hp_rgb_ycc_setup(), which HPLIP uses to install a
    # modified RGB to YCC table. src/compat/hp_csc_stub.c makes it a no-op, so
    # colors come out of the stock libjpeg converter and nobody has compared
    # them with HP's. Left out until that table is ported and checked.
    "ljjetready": "JPEG color table stubbed (see src/hpcups/UPSTREAM)",
    "quickconnect": "JPEG color table stubbed (see src/hpcups/UPSTREAM)",
}

# The queue the README has always told people to create points at this path,
# and the Status app's users have it installed. Keep it byte for byte.
LEGACY = {
    "hp-deskjet_2300_series.ppd": {
        "name": "HP DeskJet 2300 series",
        "path": "HP DeskJet 2300 series (hpcups-macos).ppd.gz",
    }
}


def read_models(path):
    models, cur = {}, None
    with open(path, errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("["):
                cur = line[1:-1]
                models[cur] = {}
            elif cur and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                models[cur][k] = v
    return models


def norm(s):
    # models.dat sometimes leaves off the leading "HP " the PPD has.
    s = re.sub(r"[^a-z0-9]+", "", s.lower())
    return s[2:] if s.startswith("hp") else s


def ppd_fields(text):
    def one(key):
        m = re.search(r'^\*%s:\s*"(.*)"' % key, text, re.M)
        return m.group(1) if m else ""

    products = re.findall(r'^\*Product:\s*"\((.*)\)"', text, re.M)
    return {
        "model": one("ModelName"),
        "language": one("hpPrinterLanguage"),
        "filter": re.search(r"^\*cupsFilter:.*", text, re.M),
        "products": products,
    }


def cmd_select(args):
    models = read_models(os.path.join(args.hplip, "data/models/models.dat"))
    idx = collections.defaultdict(set)
    for key, m in models.items():
        idx[norm(key)].add(key)
        for k, v in m.items():
            if re.fullmatch(r"model\d+", k):
                idx[norm(v)].add(key)

    kept, excluded = [], []
    for path in sorted(glob.glob(os.path.join(args.hplip, "ppd/hpcups/*.ppd.gz"))):
        name = os.path.basename(path)[: -len(".gz")]
        with gzip.open(path, "rt", errors="replace") as fh:
            text = fh.read()
        f = ppd_fields(text)
        keys = set()
        for p in f["products"] + [f["model"]]:
            keys |= idx.get(norm(p), set())
        plugins = {models[k].get("plugin", "0") for k in keys}

        reason = None
        if not f["filter"] or f["filter"].group(0).split(":", 1)[1].strip() != '"%s"' % STOCK_FILTER:
            reason = "not the hpcups raster filter"
        elif plugins - {"0"}:
            reason = "needs HP plugin (plugin=%s)" % "/".join(sorted(plugins - {"0"}))
        elif f["language"] not in LANGUAGES:
            reason = "language %s not built" % (f["language"] or "(none)")
        elif LANGUAGES[f["language"]]:
            reason = "language: " + LANGUAGES[f["language"]]
        elif not keys:
            reason = "no models.dat entry, plugin status unknown"

        row = (name, f["language"], f["model"], "|".join(f["products"]))
        if reason:
            excluded.append(row + (reason,))
        else:
            kept.append(row)
            shutil.copyfile(path, os.path.join(VENDOR, name + ".gz"))

    # Drop vendored files that are no longer selected.
    keep_names = {r[0] + ".gz" for r in kept}
    for old in glob.glob(os.path.join(VENDOR, "*.ppd.gz")):
        if os.path.basename(old) not in keep_names:
            os.remove(old)

    os.makedirs(VENDOR, exist_ok=True)
    with open(MANIFEST, "w") as fh:
        fh.write("# ppd\tlanguage\tmodel name\tproducts\n")
        for r in kept:
            fh.write("\t".join(r) + "\n")
    with open(EXCLUDED, "w") as fh:
        fh.write("# ppd\tlanguage\tmodel name\tproducts\treason\n")
        for r in excluded:
            fh.write("\t".join(r) + "\n")
    cmd_docs(args)
    print("kept %d, excluded %d" % (len(kept), len(excluded)))


def load_tsv(path):
    rows = []
    with open(path) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            rows.append(line.rstrip("\n").split("\t"))
    return rows


def cmd_docs(args):
    kept = load_tsv(MANIFEST)
    excluded = load_tsv(EXCLUDED)
    langs = collections.Counter(r[1] for r in kept)
    reasons = collections.Counter(r[4] for r in excluded)
    models = sorted(
        {(p.strip(), r[1]) for r in kept for p in (r[3].split("|") if r[3] else [r[2]])},
        key=lambda x: (x[0].lower(), x[1]),
    )

    out = [
        "<!-- Generated by scripts/gen-ppds.py docs. Do not edit. -->",
        "",
        "# Supported printers",
        "",
        "%d PPD files from HPLIP 3.25.2 cover %d model names. Every one prints "
        "through the hpcups filter in this package, with no HP plugin." % (len(kept), len(models)),
        "Only the DeskJet 2300 series has been tested on real hardware.",
        "",
        "## Print languages",
        "",
        "| Language | PPD files |",
        "| --- | ---: |",
    ]
    out += ["| %s | %d |" % (l, n) for l, n in sorted(langs.items(), key=lambda x: (-x[1], x[0]))]
    out += [
        "",
        "## Left out",
        "",
        "%d PPD files from the same HPLIP tree are not installed." % len(excluded),
        "",
        "| Reason | PPD files |",
        "| --- | ---: |",
    ]
    out += ["| %s | %d |" % (r, n) for r, n in sorted(reasons.items(), key=lambda x: (-x[1], x[0]))]
    out += [
        "",
        "The full list with reasons is `ppd/hplip/excluded.tsv`.",
        "",
        "## Models",
        "",
        "| Model | Print language |",
        "| --- | --- |",
    ]
    out += ["| %s | %s |" % (m, l) for m, l in models]
    out.append("")
    os.makedirs(os.path.dirname(DOC), exist_ok=True)
    with open(DOC, "w") as fh:
        fh.write("\n".join(out))


def repair(text):
    """Fix mistakes in HP's PPDs that cupstestppd reports as FAIL.

    A few generated PPDs list a paper size twice (Custom1, 4x6), and some
    UIConstraints name a size the PPD does not offer. CUPS tolerates both;
    cupstestppd does not. Drop the second copy and the dangling constraints.
    """
    size_opts = ("PageSize", "PageRegion", "PaperDimension", "ImageableArea")
    choice = re.compile(r"^\*(%s)\s+([^/:\s]+)" % "|".join(size_opts))
    sizes = {m.group(1) for m in re.finditer(r"^\*PageSize\s+([^/:\s]+)", text, re.M)}
    regions = {m.group(1) for m in re.finditer(r"^\*PageRegion\s+([^/:\s]+)", text, re.M)}
    seen, out = set(), []
    for line in text.split("\n"):
        m = choice.match(line)
        if m:
            if m.groups() in seen:
                continue
            seen.add(m.groups())
        c = re.match(r'^\*UIConstraints:\s*"?([^"]*)"?\s*$', line)
        if c:
            toks = c.group(1).split()
            bad = any(
                (t == "*PageSize" and toks[i + 1] not in sizes)
                or (t == "*PageRegion" and toks[i + 1] not in regions)
                for i, t in enumerate(toks[:-1])
            )
            if bad:
                continue
        out.append(line)
    return "\n".join(out)


def rewrite(text, name):
    def sub(key, value):
        nonlocal text
        text, n = re.subn(
            r'^\*%s:.*$' % key, lambda m: '*%s: "%s"' % (key, value), text, count=1, flags=re.M
        )
        if n != 1:
            raise SystemExit("no *%s line" % key)

    text = repair(text)
    sub("cupsFilter", "application/vnd.cups-raster 0 " + FILTER_PATH)
    sub("NickName", "%s, hpcups-macos" % name)
    # PPD spec: ShortNickName is at most 31 chars. Cut the model name to fit.
    tag = " hpcups-macos"
    sub("ShortNickName", name[: 31 - len(tag)].rstrip() + tag if len(name + tag) > 31 else name + tag)
    return text


def out_path(ppd):
    leg = LEGACY.get(ppd)
    if leg:
        return leg["path"], leg["name"]
    return os.path.join(SUBDIR, ppd + ".gz"), None


def cmd_build(args):
    shutil.rmtree(args.out, ignore_errors=True)
    n = 0
    for row in load_tsv(MANIFEST):
        ppd, model = row[0], row[2]
        rel, legacy_name = out_path(ppd)
        with gzip.open(os.path.join(VENDOR, ppd + ".gz"), "rt", errors="replace", newline="") as fh:
            text = fh.read()
        text = rewrite(text, legacy_name or model)
        dest = os.path.join(args.out, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as raw:
            # mtime 0 and no filename: same bytes on every build.
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as gz:
                gz.write(text.encode("utf-8", "surrogateescape"))
        n += 1
    print("wrote %d PPDs to %s" % (n, args.out))


REQUIRED = ["PCFileName", "Manufacturer", "ModelName", "NickName", "1284DeviceID",
            "hpPrinterLanguage", "cupsFilter", "PageSize"]


def cmd_check(args):
    langs = {r[0]: r[1] for r in load_tsv(MANIFEST)}
    problems = []
    seen = {}
    files = sorted(glob.glob(os.path.join(args.dir, "**", "*.ppd.gz"), recursive=True))
    if len(files) != len(langs):
        problems.append("%d PPDs built, manifest lists %d" % (len(files), len(langs)))
    for path in files:
        with gzip.open(path, "rt", errors="replace") as fh:
            text = fh.read()
        rel = os.path.relpath(path, args.dir)
        for key in REQUIRED:
            if not re.search(r"^\*(?:OpenUI \*)?%s[:/ ]" % re.escape(key), text, re.M):
                problems.append("%s: missing *%s" % (rel, key))
        m = re.search(r'^\*cupsFilter:\s*"(.*)"', text, re.M)
        if not m or m.group(1) != "application/vnd.cups-raster 0 " + FILTER_PATH:
            problems.append("%s: cupsFilter is %r" % (rel, m and m.group(1)))
        if len(re.findall(r"^\*cupsFilter2?:", text, re.M)) != 1:
            problems.append("%s: expected one cupsFilter line" % rel)
        nick = re.search(r'^\*NickName:\s*"(.*)"', text, re.M)
        if not nick or not nick.group(1).endswith(", hpcups-macos"):
            problems.append("%s: NickName %r" % (rel, nick and nick.group(1)))
        elif nick.group(1) in seen:
            problems.append("%s: NickName %r also used by %s" % (rel, nick.group(1), seen[nick.group(1)]))
        else:
            seen[nick.group(1)] = rel
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print("ok: %d PPDs pass the keyword checks" % len(files))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("select")
    s.add_argument("--hplip", required=True)
    s.set_defaults(fn=cmd_select)
    b = sp.add_parser("build")
    b.add_argument("--out", required=True)
    b.set_defaults(fn=cmd_build)
    c = sp.add_parser("check")
    c.add_argument("dir")
    c.set_defaults(fn=cmd_check)
    d = sp.add_parser("docs")
    d.set_defaults(fn=cmd_docs)
    args = ap.parse_args()
    sys.exit(args.fn(args) or 0)


if __name__ == "__main__":
    main()
