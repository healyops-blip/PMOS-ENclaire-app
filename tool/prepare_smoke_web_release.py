#!/usr/bin/env python3
"""Remove mobile-only font families from a built POMI Smoke Web release."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


FULL_FAMILY = "Noto Sans SC"
SUBSET_FAMILY = "POMI Noto Sans SC Subset"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "release",
        nargs="?",
        type=Path,
        default=Path("build/web"),
        help="Flutter Web output directory (default: build/web)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify without modifying FontManifest.json",
    )
    args = parser.parse_args()

    release = args.release.resolve()
    manifest_path = release / "assets" / "FontManifest.json"
    if not manifest_path.is_file():
        print(f"ERROR: missing {manifest_path}", file=sys.stderr)
        return 1

    manifest = json.loads(manifest_path.read_text("utf-8"))
    families = [entry.get("family") for entry in manifest]
    if SUBSET_FAMILY not in families:
        print(f"ERROR: missing subset family {SUBSET_FAMILY!r}", file=sys.stderr)
        return 1

    if not args.check:
        manifest = [entry for entry in manifest if entry.get("family") != FULL_FAMILY]
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        families = [entry.get("family") for entry in manifest]

    errors: list[str] = []
    if FULL_FAMILY in families:
        errors.append(f"mobile-only family is still present: {FULL_FAMILY}")
    if families.count(SUBSET_FAMILY) != 1:
        errors.append(f"expected exactly one subset family, found {families.count(SUBSET_FAMILY)}")

    for filename in ("index.html", "app.html"):
        html_path = release / filename
        html = html_path.read_text("utf-8")
        if "assets/assets/fonts/NotoSansSC-" in html:
            errors.append(f"{filename} still references a complete font")
        if "assets/assets/fonts/pomi_web_subset/" not in html:
            errors.append(f"{filename} does not reference the subset fonts")

    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if errors:
        return 1

    print(f"release={release}")
    print(f"font_families={','.join(str(family) for family in families)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
