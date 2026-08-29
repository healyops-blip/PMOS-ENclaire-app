"""Deterministic laboratory parsing, mapping, conversion, and validation rules."""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Any

NUMBER_PATTERN = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$")
MAX_NUMERIC_ABS = Decimal("999999999999")
RANGE_PATTERN = re.compile(
    r"^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*[-~～—]\s*"
    r"([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*$"
)
BOUND_PATTERN = re.compile(r"^\s*(<=|>=|<|>|≤|≥)\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*$")


@dataclass(frozen=True)
class MetricSpec:
    metric_id: str
    aliases: frozenset[str]
    standard_unit: str
    factors: dict[str, Decimal]


@dataclass(frozen=True)
class NormalizedLabItem:
    original_item_name: str
    standard_metric_id: str | None
    mapping_status: str
    raw_value: str
    numeric_value: Decimal
    original_unit: str
    standard_unit: str
    reference_range_raw: str | None
    reference_lower: Decimal | None
    reference_upper: Decimal | None
    abnormal_status: str
    sample_date: date | None
    exam_date: date | None
    report_date: date | None
    visit_date: date | None
    trend_date: date | None
    trend_date_source: str | None


@dataclass(frozen=True)
class FieldIssue:
    path: str
    code: str
    message: str

    def as_dict(self) -> dict[str, str]:
        return {"path": self.path, "code": self.code, "message": self.message}


def _key(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).strip().casefold()
    return re.sub(r"[\s_\-/（）()]+", "", normalized)


METRICS = (
    MetricSpec(
        "glucose",
        frozenset({_key(value) for value in ("葡萄糖", "血糖", "空腹血糖", "GLU", "glucose")}),
        "mmol/L",
        {"mmol/L": Decimal("1"), "mg/dL": Decimal("0.0555")},
    ),
    MetricSpec(
        "fasting_insulin",
        frozenset({_key(value) for value in ("胰岛素", "空腹胰岛素", "INS", "insulin")}),
        "μIU/mL",
        {"μIU/mL": Decimal("1"), "mIU/L": Decimal("1")},
    ),
    MetricSpec(
        "total_testosterone",
        frozenset({_key(value) for value in ("睾酮", "总睾酮", "TESTO", "testosterone")}),
        "nmol/L",
        {"nmol/L": Decimal("1"), "ng/dL": Decimal("0.0347")},
    ),
    MetricSpec(
        "lh",
        frozenset({_key(value) for value in ("促黄体生成素", "黄体生成素", "LH")}),
        "IU/L",
        {"IU/L": Decimal("1"), "mIU/mL": Decimal("1")},
    ),
    MetricSpec(
        "fsh",
        frozenset({_key(value) for value in ("促卵泡生成素", "卵泡刺激素", "FSH")}),
        "IU/L",
        {"IU/L": Decimal("1"), "mIU/mL": Decimal("1")},
    ),
    MetricSpec(
        "amh",
        frozenset({_key(value) for value in ("抗缪勒氏管激素", "抗苗勒管激素", "AMH")}),
        "ng/mL",
        {"ng/mL": Decimal("1"), "pmol/L": Decimal("0.140")},
    ),
    MetricSpec(
        "hba1c",
        frozenset({_key(value) for value in ("糖化血红蛋白", "HbA1c")}),
        "%",
        {"%": Decimal("1")},
    ),
)

METRIC_BY_ALIAS = {alias: spec for spec in METRICS for alias in spec.aliases}
UNIT_ALIASES = {
    "mmol/l": "mmol/L",
    "mg/dl": "mg/dL",
    "μiu/ml": "μIU/mL",
    "µiu/ml": "μIU/mL",
    "uiu/ml": "μIU/mL",
    "miu/l": "mIU/L",
    "miu/ml": "mIU/mL",
    "iu/l": "IU/L",
    "nmol/l": "nmol/L",
    "ng/dl": "ng/dL",
    "ng/ml": "ng/mL",
    "pmol/l": "pmol/L",
    "%": "%",
    "g/l": "g/L",
    "mg/l": "mg/L",
    "u/l": "U/L",
    "10^9/l": "10^9/L",
    "10*9/l": "10^9/L",
    "10⁹/l": "10^9/L",
    "10^12/l": "10^12/L",
    "10*12/l": "10^12/L",
    "10¹²/l": "10^12/L",
    "μmol/l": "μmol/L",
    "µmol/l": "μmol/L",
}


def parse_number(value: Any) -> Decimal | None:
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip().replace(",", "")
    if not NUMBER_PATTERN.fullmatch(text):
        return None
    try:
        parsed = Decimal(text)
    except InvalidOperation:
        return None
    return parsed if parsed.is_finite() else None


def normalize_unit(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip().replace(" ", "")
    # 把上标数量级 10⁹ / 10¹² 先规范成 10^9 / 10^12（必须在 NFKC 之前执行，
    # 否则 NFKC 会把上标并进数字，10⁹/L 变成 109/L 而丢失幂号）。
    sup = str.maketrans("⁰¹²³⁴⁵⁶⁷⁸⁹", "0123456789")
    text = re.sub(r"[⁰¹²³⁴⁵⁶⁷⁸⁹]+", lambda m: "^" + m.group(0).translate(sup), text)
    text = unicodedata.normalize("NFKC", text).strip()
    text = text.replace("μ", "μ").replace("µ", "µ")
    # 容忍常见的 "×10^9/L" 前导乘号（模型常以 ×/x/✕ 开头书写数量级）。
    text = re.sub(r"^[×xX✕✖*]", "", text)
    return UNIT_ALIASES.get(text.casefold())


def parse_date(value: Any) -> date | None:
    if value is None or str(value).strip() == "":
        return None
    text = unicodedata.normalize("NFKC", str(value)).strip()
    match = re.fullmatch(r"(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?", text)
    if match is None:
        return None
    try:
        return date(*(int(part) for part in match.groups()))
    except ValueError:
        return None


def _reference_bounds(
    raw: Any, factor: Decimal
) -> tuple[str | None, Decimal | None, Decimal | None, bool, bool, bool]:
    if raw is None or str(raw).strip() == "":
        return None, None, None, True, True, True
    text = unicodedata.normalize("NFKC", str(raw)).strip()
    range_match = RANGE_PATTERN.fullmatch(text)
    if range_match:
        lower = Decimal(range_match.group(1)) * factor
        upper = Decimal(range_match.group(2)) * factor
        return text, lower, upper, True, True, lower <= upper
    bound_match = BOUND_PATTERN.fullmatch(text)
    if bound_match:
        operator, number = bound_match.groups()
        boundary = Decimal(number) * factor
        if operator in {"<", "<=", "≤"}:
            return text, None, boundary, True, operator != "<", True
        return text, boundary, None, operator != ">", True, True
    return text, None, None, True, True, False


def _abnormal(
    value: Decimal,
    lower: Decimal | None,
    upper: Decimal | None,
    lower_inclusive: bool,
    upper_inclusive: bool,
) -> str:
    if lower is None and upper is None:
        return "unknown"
    if lower is not None and (value < lower or (value == lower and not lower_inclusive)):
        return "low"
    if upper is not None and (value > upper or (value == upper and not upper_inclusive)):
        return "high"
    return "normal"


def normalize_lab_item(
    item: dict[str, Any], index: int, report_dates: dict[str, Any]
) -> tuple[NormalizedLabItem | None, list[FieldIssue]]:
    prefix = f"items.{index}"
    issues: list[FieldIssue] = []
    name = str(item.get("name") or "").strip()
    if not name:
        issues.append(FieldIssue(f"{prefix}.name", "LAB_NAME_REQUIRED", "项目名称不能为空。"))
    elif len(name) > 200:
        issues.append(
            FieldIssue(f"{prefix}.name", "LAB_NAME_TOO_LONG", "项目名称不能超过 200 个字符。")
        )
    raw_value = str(item.get("value") or "").strip()
    numeric = parse_number(item.get("value"))
    if not raw_value:
        issues.append(FieldIssue(f"{prefix}.value", "LAB_VALUE_REQUIRED", "数值不能为空。"))
    elif numeric is None:
        issues.append(FieldIssue(f"{prefix}.value", "LAB_VALUE_INVALID", "数值格式无法解析。"))
    elif abs(numeric) > MAX_NUMERIC_ABS:
        issues.append(
            FieldIssue(f"{prefix}.value", "LAB_VALUE_OUT_OF_RANGE", "数值超出可保存范围。")
        )
    elif len(raw_value) > 100:
        issues.append(
            FieldIssue(f"{prefix}.value", "LAB_VALUE_TOO_LONG", "原始数值不能超过 100 个字符。")
        )
    raw_unit = str(item.get("unit") or "").strip()
    unit = normalize_unit(item.get("unit"))
    if not raw_unit:
        issues.append(FieldIssue(f"{prefix}.unit", "LAB_UNIT_REQUIRED", "单位不能为空。"))
    elif unit is None:
        issues.append(FieldIssue(f"{prefix}.unit", "LAB_UNIT_UNSUPPORTED", "单位不在允许范围内。"))
    elif len(raw_unit) > 40:
        issues.append(FieldIssue(f"{prefix}.unit", "LAB_UNIT_TOO_LONG", "单位不能超过 40 个字符。"))

    spec = METRIC_BY_ALIAS.get(_key(name)) if name else None
    factor = Decimal("1")
    standard_unit = unit or raw_unit
    if spec is not None and unit is not None:
        factor = spec.factors.get(unit, Decimal("0"))
        if factor == 0:
            issues.append(
                FieldIssue(
                    f"{prefix}.unit",
                    "LAB_UNIT_INCOMPATIBLE",
                    "该单位与已映射的指标不兼容。",
                )
            )
        standard_unit = spec.standard_unit

    reference_raw, lower, upper, lower_inclusive, upper_inclusive, reference_valid = (
        _reference_bounds(item.get("reference_range"), factor or Decimal("1"))
    )
    if not reference_valid:
        issues.append(
            FieldIssue(
                f"{prefix}.reference_range",
                "LAB_REFERENCE_RANGE_INVALID",
                "参考范围格式无法解析，请留空或输入如 3.9-6.1。",
            )
        )
    elif reference_raw is not None and len(reference_raw) > 120:
        issues.append(
            FieldIssue(
                f"{prefix}.reference_range",
                "LAB_REFERENCE_RANGE_TOO_LONG",
                "参考范围不能超过 120 个字符。",
            )
        )
    elif any(bound is not None and abs(bound) > MAX_NUMERIC_ABS for bound in (lower, upper)):
        issues.append(
            FieldIssue(
                f"{prefix}.reference_range",
                "LAB_REFERENCE_RANGE_OUT_OF_RANGE",
                "参考范围数值超出可保存范围。",
            )
        )

    parsed_dates: dict[str, date | None] = {}
    for field in ("sample_date", "exam_date", "report_date", "visit_date"):
        raw_date = item.get(field)
        if raw_date is None or str(raw_date).strip() == "":
            raw_date = report_dates.get(field)
        parsed_dates[field] = parse_date(raw_date)
        if raw_date is not None and str(raw_date).strip() and parsed_dates[field] is None:
            issues.append(
                FieldIssue(
                    f"{prefix}.{field}",
                    "LAB_DATE_INVALID",
                    "日期无效，请使用 YYYY-MM-DD。",
                )
            )

    if issues:
        return None, issues
    assert numeric is not None and unit is not None
    converted = numeric * factor
    priority = ("sample_date", "exam_date", "report_date", "visit_date")
    trend_source = next((field for field in priority if parsed_dates[field] is not None), None)
    return (
        NormalizedLabItem(
            original_item_name=name,
            standard_metric_id=None if spec is None else spec.metric_id,
            mapping_status="needs_manual_review" if spec is None else "mapped",
            raw_value=raw_value,
            numeric_value=converted,
            original_unit=raw_unit,
            standard_unit=standard_unit,
            reference_range_raw=reference_raw,
            reference_lower=lower,
            reference_upper=upper,
            abnormal_status=_abnormal(
                converted,
                lower,
                upper,
                lower_inclusive,
                upper_inclusive,
            ),
            sample_date=parsed_dates["sample_date"],
            exam_date=parsed_dates["exam_date"],
            report_date=parsed_dates["report_date"],
            visit_date=parsed_dates["visit_date"],
            trend_date=None if trend_source is None else parsed_dates[trend_source],
            trend_date_source=trend_source,
        ),
        [],
    )


def p0_evaluation(
    items: list[dict[str, Any]], original_items: list[dict[str, Any]] | None = None
) -> dict[str, int | float]:
    total = len(items) * 3
    valid = 0
    for item in items:
        valid += int(bool(str(item.get("name") or "").strip()))
        valid += int(parse_number(item.get("value")) is not None)
        valid += int(normalize_unit(item.get("unit")) is not None)
    output: dict[str, int | float] = {
        "total_fields": total,
        "valid_fields": valid,
        "invalid_fields": total - valid,
        "valid_rate": 1.0 if total == 0 else round(valid / total, 4),
    }
    if original_items is not None:
        matched = 0
        for item in items:
            source_index = item.get("source_index")
            original = (
                original_items[source_index]
                if isinstance(source_index, int) and source_index < len(original_items)
                else {}
            )
            for field in ("name", "value", "unit"):
                matched += int(
                    str(item.get(field) or "").strip() == str(original.get(field) or "").strip()
                )
        output.update(
            {
                "ocr_exact_match_fields": matched,
                "user_corrected_fields": total - matched,
                "ocr_exact_match_rate": 1.0 if total == 0 else round(matched / total, 4),
            }
        )
    return output
