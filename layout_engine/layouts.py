from typing import Dict, Any


def list_layouts() -> Dict[str, Dict[str, Any]]:
    """Return layout schema registry. Each schema declares page spec, header style, and component config."""
    # Page presets in pixels for typical printer-friendly sizes (approximate, 150–180 DPI)
    # A4 portrait ~ 1240x1754; A4 landscape ~ 1754x1240; A5 is roughly half.
    A4_P = {"size": (1240, 1754), "margins": (36, 36, 36, 36)}  # left, top, right, bottom
    A4_L = {"size": (1754, 1240), "margins": (36, 36, 36, 36)}
    A5_P = {"size": (874, 1240), "margins": (28, 28, 28, 28)}
    A5_L = {"size": (1240, 874), "margins": (28, 28, 28, 28)}

    return {
        # Classic LIS style, A4 portrait, centered hospital header, pure black/white
        "hospital_lab_01": {
            "page": A4_P,
            "header_style": "HEADER_01",
            "patient_layout": "PATIENT_01",
            "table_style": "TABLE_02",  # horizontal lines only (no verticals), classic look
            "font_style": "FONT_02",     # 全宋体
            "density": "DENSITY_MEDIUM",
            "footer_style": "FOOTER_01",
            "components": {
                # Column x ratios for lab table: No, Item, Method, Result, Unit, Ref
                "lab_table": {
                    "cols": [0.06, 0.40, 0.14, 0.14, 0.10, 0.16],
                    "row_height": 40,
                    "header_height": 44,
                    "draw_outer_box": True,
                    "draw_header_bands": True,
                    "draw_row_lines": True,
                    "draw_col_lines": False,
                },
                "notes": {"lines": 3}
            }
        },
        # A4 landscape + HEADER_03 (left hospital name, right report date, underline), dense + full grid
        "hospital_lab_03": {
            "page": A4_L,
            "header_style": "HEADER_03",
            "patient_layout": "PATIENT_02",
            "table_style": "TABLE_01",  # full grid
            "font_style": "FONT_03",     # 黑体标题 + 宋体正文
            "density": "DENSITY_HIGH",
            "footer_style": "FOOTER_01",
            "components": {
                "lab_table": {
                    "cols": [0.06, 0.38, 0.16, 0.14, 0.10, 0.16],
                    "row_height": 36,
                    "header_height": 42,
                    "draw_outer_box": True,
                    "draw_header_bands": True,
                    "draw_row_lines": True,
                    "draw_col_lines": True,
                },
                "notes": {"lines": 2}
            }
        },
        # A5 portrait + HEADER_01 for small paper, outer box only table
        "hospital_lab_05": {
            "page": A5_P,
            "header_style": "HEADER_01",
            "patient_layout": "PATIENT_04",
            "table_style": "TABLE_03",  # outer box + no inner lines
            "font_style": "FONT_01",     # 宋体+黑体
            "density": "DENSITY_LOW",
            "footer_style": "FOOTER_03",
            "components": {
                "lab_table": {
                    "cols": [0.08, 0.42, 0.16, 0.14, 0.08, 0.12],
                    "row_height": 32,
                    "header_height": 36,
                    "draw_outer_box": True,
                    "draw_header_bands": True,
                    "draw_row_lines": False,
                    "draw_col_lines": False,
                },
                "notes": {"lines": 2}
            }
        },
        # Grouped table variant on A4 portrait
        "hospital_lab_grouped": {
            "page": A4_P,
            "header_style": "HEADER_04",
            "patient_layout": "PATIENT_03",
            "table_style": "TABLE_04",
            "font_style": "FONT_03",
            "density": "DENSITY_MEDIUM",
            "footer_style": "FOOTER_02",
            "components": {
                "lab_table": {"row_height": 40, "header_height": 44},
                "notes": {"lines": 3}
            }
        },
        # Two-column results variant
        "hospital_lab_two_col": {
            "page": A4_P,
            "header_style": "HEADER_01",
            "patient_layout": "PATIENT_01",
            "table_style": "TABLE_05",
            "font_style": "FONT_02",
            "density": "DENSITY_HIGH",
            "footer_style": "FOOTER_03",
            "components": {
                "notes": {"lines": 2}
            }
        },
    }
