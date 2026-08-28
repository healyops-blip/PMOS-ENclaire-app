"""Deterministic A4 PDF rendering from an immutable snapshot JSON value only."""

from __future__ import annotations

from dataclasses import dataclass
from html import escape
from io import BytesIO
from pathlib import Path
from typing import Any

from reportlab.graphics.shapes import Drawing, Line, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    LongTable,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

SIMULATION_MARK = "模拟数据，仅供演示"
PATIENT_NOTE_DISCLAIMER = "患者自述，仅供参考，不构成诊断，不进入正式病历。"
GENERAL_DISCLAIMER = "本报告仅整理已确认数据，不提供病情、因果或用药调整结论。"
FONT_NAME = "WenQuanYiMicroHei"
FONT_PATH = Path(__file__).resolve().parents[1] / "assets" / "fonts" / "wqy-microhei.ttc"


@dataclass(frozen=True, slots=True)
class PdfContent:
    """Auditable, renderer-neutral content projection used by tests and PDF layout."""

    title: str
    generated_at: str
    snapshot_version: str
    profile_lines: tuple[str, ...]
    patient_note_lines: tuple[str, ...]
    medication_lines: tuple[str, ...]
    latest_lab_lines: tuple[str, ...]
    lab_rows: tuple[tuple[str, str, str, str, str, str], ...]
    weight_rows: tuple[tuple[str, str, str], ...]
    cycle_rows: tuple[tuple[str, str, str, str], ...]
    medication_daily_rows: tuple[tuple[str, str, str], ...]
    quality_lines: tuple[str, ...]
    source_rows: tuple[tuple[str, str, str, str, str], ...]
    disclaimers: tuple[str, ...]


def build_pdf_content(snapshot: dict[str, Any]) -> PdfContent:
    """Project only the supplied immutable snapshot; never query or merge live records."""

    metadata = _mapping(snapshot.get("metadata"))
    summary = _mapping(snapshot.get("summary"))
    trends = _mapping(snapshot.get("trends"))
    records = _mapping(snapshot.get("records"))
    profile = _mapping(summary.get("profile"))
    generated_at = _text(metadata.get("generated_at"), "未提供")
    snapshot_version = _text(metadata.get("template_version"), "unknown")

    profile_lines = (
        f"姓名/昵称：{_text(profile.get('nickname'))}",
        f"出生日期：{_text(profile.get('birth_date'))}",
        f"性别：{_text(profile.get('gender'))}",
        f"身高：{_value_unit(profile.get('height_cm'), 'cm')}",
        f"主要健康情况：{_text(profile.get('primary_condition'))}",
    )
    note = summary.get("patient_note_text")
    patient_note_lines = (
        (str(note) if note not in {None, ""} else "本次未提供患者自述。"),
        PATIENT_NOTE_DISCLAIMER,
    )
    medications = [_mapping(item) for item in _list(summary.get("current_medications"))]
    medication_lines = tuple(
        " · ".join(
            part
            for part in (
                _text(item.get("drug_name")),
                _text(item.get("specification"), ""),
                _value_unit(item.get("dosage_value"), _text(item.get("dosage_unit"), "")),
                _text(item.get("frequency"), ""),
                _text(item.get("route"), ""),
            )
            if part
        )
        for item in medications
    ) or ("暂无当前用药。",)

    latest = [_mapping(item) for item in _list(summary.get("latest_observations"))]
    latest_lab_lines = tuple(_latest_lab_line(item) for item in latest) or ("暂无最新化验指标。",)

    lab_rows: list[tuple[str, str, str, str, str, str]] = []
    quality_lines: list[str] = []
    source_dates: dict[str, str] = {}
    for trend in (_mapping(item) for item in _list(trends.get("labs"))):
        metric_name = _text(trend.get("metric_name"))
        reason = _text(trend.get("comparability_reason"), "")
        if reason:
            quality_lines.append(f"{metric_name} 不可比/谨慎比较原因：{reason}")
        for point in (_mapping(item) for item in _list(trend.get("points"))):
            point_reason = _text(point.get("exclusion_reason"), "")
            lab_rows.append(
                (
                    metric_name,
                    _text(point.get("date")),
                    _value_unit(
                        point.get("raw_value") or point.get("numeric_value"),
                        point.get("original_unit") or point.get("normalized_unit"),
                    ),
                    _text(point.get("reference_range_raw")),
                    _text(point.get("freshness")),
                    point_reason or "可比",
                )
            )
            _remember_source_date(source_dates, point)
            if point_reason:
                quality_lines.append(
                    f"{metric_name} {_text(point.get('date'))} 保留原值，"
                    f"未绘制误导性连线：{point_reason}"
                )

    weight_rows = tuple(
        (
            _text(item.get("date") or item.get("record_date")),
            _value_unit(item.get("weight_kg"), "kg"),
            _text(item.get("freshness")),
        )
        for item in (_mapping(value) for value in _list(trends.get("weights")))
    )
    for item in (_mapping(value) for value in _list(trends.get("weights"))):
        _remember_source_date(source_dates, item)

    cycle_rows = tuple(
        (
            _text(item.get("date") or item.get("start_date")),
            _text(item.get("end_date")),
            _text(item.get("flow_level")),
            _text(item.get("freshness")),
        )
        for item in (_mapping(value) for value in _list(trends.get("cycles")))
    )
    for item in (_mapping(value) for value in _list(trends.get("cycles"))):
        _remember_source_date(source_dates, item)

    medication_name_by_id = {
        str(item.get("id")): _text(item.get("drug_name"))
        for item in (_mapping(value) for value in _list(records.get("medication_history")))
    }
    medication_daily_rows = tuple(
        (
            _text(item.get("date") or item.get("record_date")),
            medication_name_by_id.get(
                str(item.get("medication_id")), _text(item.get("medication_id"))
            ),
            _text(item.get("intake_status")),
        )
        for item in (_mapping(value) for value in _list(trends.get("medication_daily")))
    )
    for item in (_mapping(value) for value in _list(trends.get("medication_daily"))):
        _remember_source_date(source_dates, item)
    record_dates: dict[str, str] = {}
    for collection_name in (
        "medication_history",
        "medication_events",
        "medical_orders",
        "imaging",
        "outpatient",
    ):
        for item in (_mapping(value) for value in _list(records.get(collection_name))):
            _remember_source_date(source_dates, item)
            record_date = _record_material_date(item)
            if item.get("id") is not None and record_date:
                record_dates[str(item["id"])] = record_date

    missing = [_text(value) for value in _list(summary.get("missing_sections"))]
    quality_lines.insert(0, f"缺失资料：{', '.join(missing) if missing else '无'}")
    quality_lines.append("新鲜度：current≤92天；caution≤183天；stale≤366天；archived>366天。")

    source_rows = tuple(
        (
            str(item.get("source_number", "-")),
            _text(item.get("source_type")),
            source_dates.get(str(item.get("source_number")))
            or record_dates.get(str(item.get("source_record_id")))
            or "未提供",
            "患者手工记录"
            if item.get("origin_kind") == "patient_manual"
            else _text(item.get("origin_kind")),
            (
                f"修订 {item['document_revision_id']}"
                if item.get("document_revision_id")
                else "无文档修订（手工/系统/规则来源）"
            ),
        )
        for item in (_mapping(value) for value in _list(snapshot.get("sources")))
    )
    supplied_disclaimers = tuple(
        _text(value) for value in _list(summary.get("disclaimers")) if _text(value, "")
    )
    required_disclaimers = (SIMULATION_MARK, PATIENT_NOTE_DISCLAIMER, GENERAL_DISCLAIMER)
    disclaimers = tuple(dict.fromkeys((*required_disclaimers, *supplied_disclaimers)))
    return PdfContent(
        title="POMI 健康资料报告",
        generated_at=generated_at,
        snapshot_version=snapshot_version,
        profile_lines=profile_lines,
        patient_note_lines=patient_note_lines,
        medication_lines=medication_lines,
        latest_lab_lines=latest_lab_lines,
        lab_rows=tuple(lab_rows),
        weight_rows=weight_rows,
        cycle_rows=cycle_rows,
        medication_daily_rows=medication_daily_rows,
        quality_lines=tuple(dict.fromkeys(quality_lines)),
        source_rows=source_rows,
        disclaimers=disclaimers,
    )


def render_report_pdf(snapshot: dict[str, Any], *, font_path: Path = FONT_PATH) -> bytes:
    content = build_pdf_content(snapshot)
    _register_font(font_path)
    output = BytesIO()
    margin = 18 * mm
    doc = BaseDocTemplate(
        output,
        pagesize=A4,
        leftMargin=margin,
        rightMargin=margin,
        topMargin=24 * mm,
        bottomMargin=22 * mm,
        title=content.title,
        author="POMI",
        subject=SIMULATION_MARK,
        creator=f"POMI {content.snapshot_version}",
        pageCompression=1,
        invariant=1,
    )
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="normal")
    doc.addPageTemplates(
        [PageTemplate(id="report", frames=[frame], onPage=_page_decorator(content))]
    )
    story = _story(content, doc.width)
    doc.build(story)
    return output.getvalue()


def _story(content: PdfContent, width: float) -> list[Any]:
    styles = getSampleStyleSheet()
    body = ParagraphStyle(
        "PomiBody", parent=styles["BodyText"], fontName=FONT_NAME, fontSize=9.5, leading=15
    )
    small = ParagraphStyle(
        "PomiSmall", parent=body, fontSize=8, leading=11, textColor=colors.HexColor("#5F5A69")
    )
    heading = ParagraphStyle(
        "PomiHeading",
        parent=styles["Heading2"],
        fontName=FONT_NAME,
        fontSize=13,
        leading=18,
        textColor=colors.HexColor("#6547A8"),
        spaceBefore=8,
        spaceAfter=6,
        keepWithNext=True,
    )
    title = ParagraphStyle(
        "PomiTitle",
        parent=styles["Title"],
        fontName=FONT_NAME,
        fontSize=22,
        leading=28,
        alignment=TA_CENTER,
        textColor=colors.HexColor("#553691"),
    )
    story: list[Any] = [
        Paragraph(escape(content.title), title),
        Paragraph(
            escape(f"报告生成时间：{content.generated_at}　快照版本：{content.snapshot_version}"),
            small,
        ),
        Spacer(1, 5 * mm),
    ]

    def lines_section(name: str, lines: tuple[str, ...]) -> None:
        story.append(Paragraph(escape(name), heading))
        story.append(
            KeepTogether(
                [Paragraph(escape(line), body) for line in lines] or [Paragraph("—", body)]
            )
        )

    lines_section("患者基本信息", content.profile_lines)
    lines_section("本次患者自述", content.patient_note_lines)
    lines_section("当前用药", content.medication_lines)
    lines_section("最新指标与参考范围状态", content.latest_lab_lines)
    story.extend(_trend_chart(content.weight_rows, "体重趋势", 1, width, body, heading))
    story.extend(_cycle_chart(content.cycle_rows, width, body, heading))
    story.extend(
        _long_table(
            "化验完整趋势（历史数据完整保留）",
            ("指标", "日期", "原值/单位", "参考范围", "新鲜度", "比较说明"),
            content.lab_rows,
            width,
            body,
            small,
            heading,
        )
    )
    story.extend(
        _long_table(
            "本月及历史用药记录表",
            ("日期", "用药记录编号", "服用状态"),
            content.medication_daily_rows,
            width,
            body,
            small,
            heading,
        )
    )
    lines_section("资料完整性、新鲜度与不可比说明", content.quality_lines)
    story.extend(
        _long_table(
            "来源附录",
            ("来源编号", "来源类型", "材料日期", "来源属性", "修订标识"),
            content.source_rows,
            width,
            body,
            small,
            heading,
        )
    )
    story.append(Paragraph("免责声明", heading))
    story.append(KeepTogether([Paragraph(escape(value), body) for value in content.disclaimers]))
    return story


def _long_table(
    title: str,
    headers: tuple[str, ...],
    rows: tuple[tuple[str, ...], ...],
    width: float,
    body: ParagraphStyle,
    small: ParagraphStyle,
    heading: ParagraphStyle,
) -> list[Any]:
    display_rows = rows or (tuple("暂无" if index == 0 else "—" for index in range(len(headers))),)
    data = [[Paragraph(escape(value), small) for value in headers]]
    data.extend([Paragraph(escape(_text(value)), small) for value in row] for row in display_rows)
    table = LongTable(
        data,
        repeatRows=1,
        colWidths=[width / len(headers)] * len(headers),
        splitByRow=1,
        hAlign="LEFT",
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EDE5FA")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#4C347A")),
                ("FONTNAME", (0, 0), (-1, -1), FONT_NAME),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#CFC5DC")),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return [Paragraph(escape(title), heading), table, Spacer(1, 2 * mm)]


def _trend_chart(
    rows: tuple[tuple[str, ...], ...],
    title: str,
    value_index: int,
    width: float,
    body: ParagraphStyle,
    heading: ParagraphStyle,
) -> list[Any]:
    if not rows:
        return [Paragraph(escape(title), heading), Paragraph("暂无记录。", body)]
    values: list[float] = []
    for row in rows:
        try:
            values.append(float(row[value_index].split()[0]))
        except (ValueError, IndexError):
            values.append(0)
    drawing = Drawing(width, 90)
    drawing.add(Line(20, 18, width - 15, 18, strokeColor=colors.HexColor("#B8AEC9")))
    minimum, maximum = min(values), max(values)
    span = maximum - minimum or 1
    points: list[tuple[float, float]] = []
    for index, value in enumerate(values):
        x = 24 + index * ((width - 52) / max(len(values) - 1, 1))
        y = 24 + (value - minimum) / span * 48
        points.append((x, y))
        drawing.add(String(x - 8, 4, rows[index][0], fontName=FONT_NAME, fontSize=6))
    for start, end in zip(points, points[1:], strict=False):
        drawing.add(Line(*start, *end, strokeColor=colors.HexColor("#7B6BDA"), strokeWidth=1.5))
    for x, y in points:
        drawing.add(Line(x - 2, y, x + 2, y, strokeColor=colors.HexColor("#D250F7"), strokeWidth=4))
    legend = Paragraph("图例：紫线连接按日期可比较的记录；全部原始行仍保留在报告中。", body)
    return [Paragraph(escape(title), heading), KeepTogether([drawing, legend])]


def _cycle_chart(
    rows: tuple[tuple[str, ...], ...],
    width: float,
    body: ParagraphStyle,
    heading: ParagraphStyle,
) -> list[Any]:
    if not rows:
        return [Paragraph("经期趋势", heading), Paragraph("暂无记录。", body)]
    table = Table(
        [[Paragraph(escape(value), body) for value in ("开始", "结束", "流量", "新鲜度")]]
        + [[Paragraph(escape(value), body) for value in row] for row in rows],
        colWidths=[width / 4] * 4,
        repeatRows=1,
        splitByRow=1,
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F3ECFA")),
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#CFC5DC")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    return [Paragraph("经期趋势", heading), table]


def _page_decorator(content: PdfContent):
    def decorate(canvas: Canvas, doc: BaseDocTemplate) -> None:
        canvas.saveState()
        canvas.setFont(FONT_NAME, 7.5)
        canvas.setFillColor(colors.HexColor("#6C6375"))
        canvas.drawString(doc.leftMargin, A4[1] - 13 * mm, f"版本 {content.snapshot_version}")
        canvas.drawRightString(A4[0] - doc.rightMargin, A4[1] - 13 * mm, SIMULATION_MARK)
        canvas.drawString(doc.leftMargin, 10 * mm, SIMULATION_MARK)
        canvas.drawRightString(A4[0] - doc.rightMargin, 10 * mm, f"第 {doc.page} 页")
        canvas.restoreState()

    return decorate


def _register_font(font_path: Path) -> None:
    if FONT_NAME in pdfmetrics.getRegisteredFontNames():
        return
    if not font_path.is_file():
        raise FileNotFoundError("Bundled CJK font is unavailable")
    pdfmetrics.registerFont(TTFont(FONT_NAME, font_path, subfontIndex=0))


def _remember_source_date(target: dict[str, str], item: dict[str, Any]) -> None:
    number = item.get("source_number")
    value = item.get("date") or item.get("record_date")
    if number is not None and value:
        target.setdefault(str(number), str(value))


def _latest_lab_line(item: dict[str, Any]) -> str:
    value = _value_unit(
        item.get("raw_value") or item.get("numeric_value"), item.get("original_unit")
    )
    return (
        f"{_text(item.get('original_item_name'))}：{value}；"
        f"参考范围 {_text(item.get('reference_range_raw'))}；"
        f"状态 {_text(item.get('abnormal_status'))}"
    )


def _record_material_date(item: dict[str, Any]) -> str | None:
    for key in (
        "date",
        "record_date",
        "event_date",
        "order_date",
        "examination_date",
        "report_date",
        "visit_date",
        "start_date",
    ):
        value = item.get(key)
        if value:
            return str(value)
    return None


def _mapping(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _text(value: Any, fallback: str = "未提供") -> str:
    return str(value) if value is not None and value != "" else fallback


def _value_unit(value: Any, unit: Any) -> str:
    text = _text(value)
    unit_text = _text(unit, "")
    return f"{text} {unit_text}".strip()
