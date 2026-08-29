#!/usr/bin/env python3
"""Build and verify the POMI Flutter Web font subsets.

The mobile app keeps the complete Noto Sans SC files. Flutter Web uses the
generated subset family so its CanvasKit renderer does not need to download
four roughly 10 MiB CJK fonts during the smoke-demo flow.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from fontTools import subset
    from fontTools.ttLib import TTFont
except ImportError as exc:  # pragma: no cover - command-line dependency guard
    raise SystemExit(
        "fontTools is required. Install it explicitly with: "
        f"{sys.executable} -m pip install fonttools"
    ) from exc


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = PROJECT_ROOT / "assets" / "fonts" / "pomi_web_subset"
FONT_FILES = (
    "NotoSansSC-Regular.ttf",
    "NotoSansSC-Medium.ttf",
    "NotoSansSC-Bold.ttf",
    "NotoSansSC-ExtraBold.ttf",
)
TEXT_ROOTS = (
    PROJECT_ROOT / "lib",
    PROJECT_ROOT / "assets" / "data",
    PROJECT_ROOT / "web",
)
TEXT_SUFFIXES = {".dart", ".html", ".json", ".js", ".svg", ".yaml", ".yml"}
MAX_TOTAL_BYTES = 8 * 1024 * 1024

# Keep the printable ASCII range even when a character is assembled at runtime,
# plus punctuation frequently produced by dates, measurements, and user input.
ALWAYS_INCLUDE = (
    set(range(0x20, 0x7F))
    | {
        0x00A0,
        0x00B7,
        0x00D7,
        0x2013,
        0x2014,
        0x2018,
        0x2019,
        0x201C,
        0x201D,
        0x2022,
        0x2026,
        0x2103,
        0x2190,
        0x2191,
        0x2192,
        0x2193,
        0x2212,
        0x3000,
        0x3001,
        0x3002,
        0x300A,
        0x300B,
        0x3010,
        0x3011,
        0xFF01,
        0xFF08,
        0xFF09,
        0xFF0C,
        0xFF1A,
        0xFF1B,
        0xFF1F,
        0xFFFD,
    }
)


def collect_codepoints() -> set[int]:
    codepoints = set(ALWAYS_INCLUDE)
    for root in TEXT_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
                continue
            codepoints.update(ord(character) for character in path.read_text("utf-8"))
    return codepoints


def cmap_codepoints(path: Path) -> set[int]:
    with TTFont(path, lazy=True) as font:
        return set(font.getBestCmap() or {})


def build_subset(source: Path, destination: Path, codepoints: set[int]) -> None:
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    options.recalc_average_width = True
    options.recalc_max_context = True

    font = subset.load_font(str(source), options)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)
    subset.save_font(font, str(destination), options)


def verify(codepoints: set[int]) -> list[str]:
    errors: list[str] = []
    total_bytes = 0
    for filename in FONT_FILES:
        source = PROJECT_ROOT / "assets" / "fonts" / filename
        destination = OUTPUT_DIR / filename
        if not destination.is_file():
            errors.append(f"missing subset: {destination.relative_to(PROJECT_ROOT)}")
            continue
        expected = codepoints & cmap_codepoints(source)
        actual = cmap_codepoints(destination)
        missing = expected - actual
        if missing:
            preview = ", ".join(f"U+{value:04X}" for value in sorted(missing)[:10])
            errors.append(f"{filename} is missing {len(missing)} glyphs ({preview})")
        total_bytes += destination.stat().st_size

    if total_bytes > MAX_TOTAL_BYTES:
        errors.append(
            f"subset fonts total {total_bytes} bytes exceeds the {MAX_TOTAL_BYTES}-byte budget"
        )
    if not errors:
        print(f"codepoints={len(codepoints)}")
        print(f"subset_total_bytes={total_bytes}")
        for filename in FONT_FILES:
            source = PROJECT_ROOT / "assets" / "fonts" / filename
            destination = OUTPUT_DIR / filename
            print(
                f"{filename}: {source.stat().st_size} -> {destination.stat().st_size} bytes"
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify existing subset files without rewriting them",
    )
    args = parser.parse_args()

    codepoints = collect_codepoints()
    if not args.check:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        for filename in FONT_FILES:
            build_subset(
                PROJECT_ROOT / "assets" / "fonts" / filename,
                OUTPUT_DIR / filename,
                codepoints,
            )

    errors = verify(codepoints)
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
