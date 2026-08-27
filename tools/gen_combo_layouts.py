import os
import sys
import json
import random
from pathlib import Path
from itertools import product

# Ensure repo root on sys.path
REPO_ROOT = str(Path(__file__).resolve().parents[1])
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from layout_engine.engine import generate_report
from report_types import get_report_type
from case_generalize import HOSPITALS, DEPARTMENTS


# Page presets (match layout_engine/layouts.py comments)
PAGE_PRESETS = {
    "A4_P": {"size": (1240, 1754), "margins": (36, 36, 36, 36)},
    "A4_L": {"size": (1754, 1240), "margins": (36, 36, 36, 36)},
    "A5_P": {"size": (874, 1240), "margins": (28, 28, 28, 28)},
    "A5_L": {"size": (1240, 874), "margins": (28, 28, 28, 28)},
}

HEADERS = ["HEADER_01", "HEADER_02", "HEADER_03", "HEADER_04"]
PATIENTS = ["PATIENT_01", "PATIENT_02", "PATIENT_03", "PATIENT_04"]
TABLES = ["TABLE_01", "TABLE_02", "TABLE_03", "TABLE_04", "TABLE_05"]
FONTS = ["FONT_01", "FONT_02", "FONT_03", "FONT_04"]
DENSITIES = ["DENSITY_LOW", "DENSITY_MEDIUM", "DENSITY_HIGH"]
FOOTERS = ["FOOTER_01", "FOOTER_02", "FOOTER_03"]


def build_content(report_type: str) -> dict:
    module = get_report_type(report_type)
    data = module.generate_data()
    content = dict(data)
    content.setdefault("report_type", report_type)
    content.setdefault("department", random.choice(DEPARTMENTS))
    content["gender"] = "女"
    content.setdefault("title", "检验报告单" if report_type == "化验_检测报告" else report_type)
    return content


def schema_for_combo(page_key: str, header: str, patient: str, table: str, font: str, density: str, footer: str):
    page = dict(PAGE_PRESETS[page_key])
    components = {}
    # Provide a generic lab_table config that works across styles
    lab_table = {
        "cols": [0.06, 0.40, 0.14, 0.14, 0.10, 0.16],
        "cols_grouped": [0.50, 0.20, 0.14, 0.16],
        "row_height": 38,
        "header_height": 44,
        "draw_outer_box": True,
        "draw_header_bands": True,
        "draw_row_lines": True,
        "draw_col_lines": (table == "TABLE_01"),
    }
    if table == "TABLE_03":
        lab_table["draw_row_lines"] = False
        lab_table["draw_col_lines"] = False
    components["lab_table"] = lab_table
    components["notes"] = {"lines": 2 if density != "DENSITY_HIGH" else 1}

    return {
        "page": page,
        "header_style": header,
        "patient_layout": patient,
        "table_style": table,
        "font_style": font,
        "density": density,
        "footer_style": footer,
        "components": components,
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Generate N distinct layout combos into one folder (lab reports)")
    parser.add_argument("--output", required=True)
    parser.add_argument("--count", type=int, default=30)
    parser.add_argument("--font-path", default="C:\\Windows\\Fonts\\simsun.ttc")
    args = parser.parse_args()

    report_type = "化验_检测报告"
    out_dir = os.path.join(args.output, report_type)
    os.makedirs(out_dir, exist_ok=True)

    # Cartesian product of options, then pick first N after shuffling for diversity
    combos = list(product(PAGE_PRESETS.keys(), HEADERS, PATIENTS, TABLES, FONTS, DENSITIES, FOOTERS))
    random.seed(42)
    random.shuffle(combos)
    combos = combos[: args.count]

    # Determine start index based on existing files
    start_index = 1
    try:
        existing = [
            int(fn[5:10])
            for fn in os.listdir(out_dir)
            if fn.startswith("case_") and fn.endswith(".jpg") and fn[5:10].isdigit()
        ]
        if existing:
            start_index = max(existing) + 1
    except Exception:
        start_index = 1

    for idx, (page_key, header, patient, table, font, density, footer) in enumerate(combos, start=start_index):
        schema = schema_for_combo(page_key, header, patient, table, font, density, footer)
        content = build_content(report_type)
        # choose hospital
        hosp = random.choice(HOSPITALS)
        # Strip latin/english tail
        import re
        name = hosp["name"]
        m = re.search(r"[A-Za-z]", name)
        if m:
            name = name[:m.start()]
        content["hospital"] = name.strip() or hosp["name"]
        content["patient_id"] = f"LA{idx:05d}"

        filename = f"case_{idx:05d}.jpg"
        out_path = os.path.join(out_dir, filename)
        config = {"font_path": args.font_path, "jpeg_quality": 95}
        generate_report(content=content, layout=schema, output_path=out_path, config=config)

        meta = {
            "report_type": report_type,
            "layout": {
                "page": page_key,
                "header_style": header,
                "patient_layout": patient,
                "table_style": table,
                "font_style": font,
                "density": density,
                "footer_style": footer,
            },
            "content": content,
        }
        with open(out_path.replace('.jpg', '.json'), 'w', encoding='utf-8') as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)

    print(f"Done. Output: {out_dir} (generated {len(combos)} combos)")


if __name__ == "__main__":
    main()
