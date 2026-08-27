import os
from typing import Dict, Any, Tuple, List
from PIL import Image, ImageDraw, ImageFont
from .layouts import list_layouts


def _load_font(font_path: str, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(font_path, size)
    except Exception:
        # Fallback to Windows defaults
        for p in [
            "C:\\Windows\\Fonts\\msyh.ttc",
            "C:\\Windows\\Fonts\\simkai.ttf",
            "C:\\Windows\\Fonts\\simsun.ttc",
        ]:
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
        return ImageFont.load_default()


def _text(draw: ImageDraw.ImageDraw, box: Tuple[int, int, int, int], text: str, font: ImageFont.FreeTypeFont, fill=(0, 0, 0), align="left"):
    x1, y1, x2, y2 = box
    w = x2 - x1
    h = y2 - y1
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    if align == "center":
        tx = x1 + (w - tw) / 2
    elif align == "right":
        tx = max(x1, x2 - tw - 1)
    else:
        tx = x1 + 1
    ty = y1 + (h - th) / 2
    draw.text((tx, ty), text, font=font, fill=fill)


def _choose_font_paths(font_style: str, config: Dict[str, Any]) -> Dict[str, str]:
    # Determine preferred font files for title/body based on style
    # Defaults: SimSun for body; SimHei for bold titles; YaHei as sans alternative
    body = config.get("font_path", "C:\\Windows\\Fonts\\simsun.ttc")
    song = "C:\\Windows\\Fonts\\simsun.ttc"
    hei = "C:\\Windows\\Fonts\\simhei.ttf"
    yahei = "C:\\Windows\\Fonts\\msyh.ttc"
    if font_style == "FONT_01":  # 宋体 + 黑体
        return {"title": hei, "header": hei, "body": song, "small": song}
    if font_style == "FONT_02":  # 全宋体
        return {"title": song, "header": song, "body": song, "small": song}
    if font_style == "FONT_03":  # 黑体标题 + 宋体正文
        return {"title": hei, "header": hei, "body": song, "small": song}
    if font_style == "FONT_04":  # 小号无衬线（医院打印）
        return {"title": yahei, "header": yahei, "body": yahei, "small": yahei}
    return {"title": body, "header": body, "body": body, "small": body}


def _size_profile(density: str) -> Dict[str, int]:
    # Return font sizes and spacing tweaks for a given density
    if density == "DENSITY_LOW":
        return {"hosp": 40, "title": 22, "header": 18, "body": 20, "small": 18, "row_delta": 4}
    if density == "DENSITY_HIGH":
        return {"hosp": 34, "title": 20, "header": 16, "body": 16, "small": 14, "row_delta": -4}
    return {"hosp": 36, "title": 22, "header": 18, "body": 18, "small": 16, "row_delta": 0}


def _draw_header(draw: ImageDraw.ImageDraw, page: Dict[str, Any], schema: Dict[str, Any], content: Dict[str, Any], fonts: Dict[str, ImageFont.FreeTypeFont], y: int, skip_logo: bool = True) -> int:
    W, H = page["size"]
    left, top, right, bottom = page["margins"]
    header = schema["header_style"]
    hospital = content.get("hospital", "")
    title = content.get("title", content.get("report_type", "检验报告单"))
    date = content.get("exam_date", "")
    # Fonts
    f_hosp = fonts["hosp"]
    f_title = fonts["title"]
    f_small = fonts["small"]

    if header == "HEADER_01":
        # Center hospital name, then report title under it
        _text(draw, (left, y, W - right, y + 44), hospital, f_hosp, align="center")
        y += 44
        _text(draw, (left, y, W - right, y + 30), title, f_title, align="center")
        y += 30 + 8
    elif header == "HEADER_02":
        # Logo left (optional), hospital centered, type under hospital
        logo_w = 96
        if not skip_logo and content.get("logo_path"):
            try:
                logo = Image.open(content["logo_path"]).convert("RGBA")
                ratio = logo_w / max(1, logo.width)
                logo = logo.resize((int(logo.width * ratio), int(logo.height * ratio)))
                draw.im.image.paste(logo, (left, y), logo)
            except Exception:
                pass
        _text(draw, (left, y, W - right, y + 44), hospital, f_hosp, align="center")
        y += 44
        _text(draw, (left, y, W - right, y + 28), title, f_title, align="center")
        y += 28 + 8
    elif header == "HEADER_03":
        # Hospital left, date right, underline
        _text(draw, (left, y, left + int((W - left - right) * 0.6), y + 36), hospital, f_hosp, align="left")
        _text(draw, (W - right - 300, y, W - right, y + 22), f"报告日期：{date}", f_small, align="right")
        y += 40
        draw.line([left, y, W - right, y], fill=(0, 0, 0), width=2)
        y += 10
    elif header == "HEADER_04":
        # Hospital centered; english under; report type on right side
        hosp_cn = content.get("hospital_cn") or hospital
        hosp_en = content.get("hospital_en", "")
        _text(draw, (left, y, W - right, y + 40), hosp_cn, f_hosp, align="center")
        y += 38
        if hosp_en:
            _text(draw, (left, y, W - right, y + 24), hosp_en, f_small, align="center")
            y += 24
        _text(draw, (W - right - 280, y - 40, W - right, y - 16), title, f_title, align="right")
        y += 8
    else:
        # Default to HEADER_01 behavior to avoid NPEs
        _text(draw, (left, y, W - right, y + 44), hospital, f_hosp, align="center")
        y += 44
        _text(draw, (left, y, W - right, y + 30), title, f_title, align="center")
        y += 30 + 8
    return y


def _draw_patient_info(draw: ImageDraw.ImageDraw, page: Dict[str, Any], y: int, content: Dict[str, Any], fonts: Dict[str, ImageFont.FreeTypeFont]) -> int:
    W, H = page["size"]
    left, top, right, bottom = page["margins"]
    f = fonts["body"]
    # Switch by patient layout style if provided in schema
    layout = page.get("patient_layout") or "PATIENT_01"  # fallback
    # If not found on page, engine caller should pass chosen layout via schema-level key; so prefer schema on caller side
    # For compatibility, allow the schema to put this key at root; engine will fetch in caller
    # Here we implement 4 layouts per the spec
    def row(h, t):
        _text(draw, h, t, f, align="left")

    name = content.get('name','')
    gender = content.get('gender','')
    age = content.get('age','')
    dept = content.get('department','')
    pid = content.get('patient_id','')
    doctor = content.get('doctor','')
    date_label = "检查日期" if content.get("report_type") in ("影像文字报告", "化验_检测报告") else "就诊日期"
    date_val = content.get('exam_date','')

    if layout == "PATIENT_01":
        # 横向多列
        line = f"姓名：{name}      性别：{gender}      年龄：{age}岁      科室：{dept}      就诊号：{pid}"
        row((left, y, W - right, y + 26), line)
        y += 30
        row((left, y, W - right, y + 24), f"{date_label}：{date_val}      申请医生：{doctor}" )
        y += 24
    elif layout == "PATIENT_02":
        # 两行网格
        colw = (W - left - right) // 3
        row((left + 0*colw, y, left + 1*colw, y + 24), f"姓名：{name}")
        row((left + 1*colw, y, left + 2*colw, y + 24), f"性别：{gender}")
        row((left + 2*colw, y, left + 3*colw, y + 24), f"年龄：{age}岁")
        y += 26
        row((left + 0*colw, y, left + 1*colw, y + 24), f"科室：{dept}")
        row((left + 1*colw, y, left + 2*colw, y + 24), f"就诊号：{pid}")
        row((left + 2*colw, y, left + 3*colw, y + 24), f"申请医生：{doctor}")
        y += 26
        row((left, y, W - right, y + 24), f"{date_label}：{date_val}")
        y += 20
    elif layout == "PATIENT_03":
        # 左信息 + 右二维码（二维码可后续接入，当前预留占位方框）
        info_w = int((W - left - right) * 0.7)
        row((left, y, left + info_w, y + 24), f"姓名：{name}    性别：{gender}    年龄：{age}岁    科室：{dept}")
        y += 26
        row((left, y, left + info_w, y + 24), f"就诊号：{pid}    申请医生：{doctor}    {date_label}：{date_val}")
        # QR placeholder on right
        qr_left = left + info_w + 16
        qr_size = 96
        draw.rectangle([qr_left, y - 26, qr_left + qr_size, y - 26 + qr_size], outline=(0,0,0), width=1)
        y += 10
    elif layout == "PATIENT_04":
        # 标签式
        row((left, y, W - right, y + 24), "患者：")
        y += 24
        row((left + 24, y, W - right, y + 22), f"姓名 {name}")
        y += 22
        row((left + 24, y, W - right, y + 22), f"性别 {gender}")
        y += 22
        row((left + 24, y, W - right, y + 22), f"年龄 {age}")
        y += 22
        row((left + 24, y, W - right, y + 22), f"科室 {dept}    就诊号 {pid}")
        y += 22
        row((left + 24, y, W - right, y + 22), f"{date_label} {date_val}    申请医生 {doctor}")
        y += 10
    else:
        # default fallback: PATIENT_01
        line = f"姓名：{name}      性别：{gender}      年龄：{age}岁      科室：{dept}      就诊号：{pid}"
        row((left, y, W - right, y + 26), line)
        y += 30
        row((left, y, W - right, y + 24), f"{date_label}：{date_val}      申请医生：{doctor}" )
        y += 24
    return y


def _draw_lab_table(draw: ImageDraw.ImageDraw, page: Dict[str, Any], y: int, content: Dict[str, Any], schema: Dict[str, Any], fonts: Dict[str, ImageFont.FreeTypeFont]) -> int:
    W, H = page["size"]
    left, top, right, bottom = page["margins"]
    cfg = schema["components"].get("lab_table", {})
    table_style = schema.get("table_style", "TABLE_02")
    header_h = page.get("_header_h", cfg.get("header_height", 44))
    row_h = page.get("_row_h", cfg.get("row_height", 40))
    # Compute absolute x positions
    width = W - left - right
    xs = [left]
    # Prepare columns depending on table style; some styles don't need 'cols'
    if table_style in ("TABLE_01", "TABLE_02", "TABLE_03"):
        cols_ratio = cfg.get("cols", [0.06, 0.40, 0.14, 0.14, 0.10, 0.16])
        for r in cols_ratio:
            xs.append(xs[-1] + int(width * r))
    elif table_style == "TABLE_04":
        # Grouped: 4 columns
        cols_ratio = cfg.get("cols_grouped", [0.50, 0.20, 0.14, 0.16])
        for r in cols_ratio:
            xs.append(xs[-1] + int(width * r))
    elif table_style == "TABLE_05":
        # Two-column: center divider
        xs = [left, left + width // 2, W - right]
    # Header bands (thick lines)
    f_head = fonts["header"]
    f_body = fonts["body"]
    if table_style in ("TABLE_01", "TABLE_02", "TABLE_03"):
        if cfg.get("draw_header_bands", True):
            draw.line([left, y, W - right, y], fill=(0, 0, 0), width=2)
        headers = ["序号", "项目名称", "方法", "结果", "单位", "参考范围"]
        for i, hname in enumerate(headers):
            _text(draw, (xs[i] + 6, y + 2, xs[i + 1] - 6, y + header_h - 2), hname, f_head, align="left")
        y += header_h
        draw.line([left, y, W - right, y], fill=(0, 0, 0), width=2)
    elif table_style == "TABLE_04":
        # Group title
        _text(draw, (left, y, W - right, y + header_h), "生化指标", f_head, align="left")
        y += header_h - 6
        draw.line([left, y, W - right, y], fill=(0, 0, 0), width=2)
        # Subtable headers: 项目 | 结果 | 单位 | 参考范围
        headers = ["项目", "结果", "单位", "参考范围"]
        for i, hname in enumerate(headers):
            _text(draw, (xs[i] + 6, y + 2, xs[i + 1] - 6, y + header_h - 2), hname, f_head, align="left")
        y += header_h
        draw.line([left, y, W - right, y], fill=(0, 0, 0), width=2)
    elif table_style == "TABLE_05":
        # Two-column: left names, right results
        # Draw header line
        draw.line([left, y, W - right, y], fill=(0, 0, 0), width=2)
        y += 6

    # Optional vertical lines for standard tables
    if table_style in ("TABLE_01", "TABLE_02"):
        if cfg.get("draw_col_lines", False) or table_style == "TABLE_01":
            for xline in xs:
                draw.line([xline, y - header_h, xline, min(H - bottom - 150, y + row_h * 12)], fill=(0, 0, 0), width=1)
            draw.line([W - right, y - header_h, W - right, min(H - bottom - 150, y + row_h * 12)], fill=(0, 0, 0), width=1)

    # Data rows we will render from content; choose key items consistent with existing generation
    rows: List[Tuple[str, str, str, str, str]] = [
        ("白细胞计数(WBC)", "自动", str(content.get("wbc", "")), "×10^9/L", "4-12"),
        ("红细胞计数(RBC)", "自动", str(content.get("rbc", "")), "×10^12/L", "4-6"),
        ("血红蛋白(HGB)", "比色", str(content.get("hgb", "")), "g/L", "110-180"),
        ("血小板计数(PLT)", "自动", str(content.get("plt", "")), "×10^9/L", "100-350"),
        ("谷丙转氨酶(ALT)", "速率法", str(content.get("alt", "")), "U/L", "5-45"),
        ("谷草转氨酶(AST)", "速率法", str(content.get("ast", "")), "U/L", "5-45"),
        ("空腹血糖(GLU)", "酶法", str(content.get("glu", "")), "mmol/L", "3-8"),
        ("高密度脂蛋白(HDL)", "直接法", str(content.get("hdl", "")), "mmol/L", "0.8-2.0"),
        ("低密度脂蛋白(LDL)", "直接法", str(content.get("ldl", "")), "mmol/L", "2-4"),
    ]
    if table_style in ("TABLE_01", "TABLE_02", "TABLE_03"):
        for idx, (item, method, val, unit, ref) in enumerate(rows, 1):
            y1 = y + (idx - 1) * row_h
            # Row line (thin)
            draw_rows = cfg.get("draw_row_lines", True)
            if table_style == "TABLE_03":
                draw_rows = False
            if draw_rows:
                draw.line([left, y1, W - right, y1], fill=(0, 0, 0), width=1)
            # No
            _text(draw, (xs[0] + 6, y1, xs[1] - 6, y1 + row_h), f"{idx}", f_body, align="left")
            # Item
            _text(draw, (xs[1] + 6, y1, xs[2] - 6, y1 + row_h), item, f_body, align="left")
            # Method
            _text(draw, (xs[2] + 6, y1, xs[3] - 6, y1 + row_h), method, f_body, align="left")
            # Result (right aligned)
            _text(draw, (xs[3] + 6, y1, xs[4] - 6, y1 + row_h), val, f_body, align="right")
            # Unit
            _text(draw, (xs[4] + 6, y1, xs[5] - 6, y1 + row_h), unit, f_body, align="left")
            # Ref range
            _text(draw, (xs[5] + 6, y1, xs[6] - 6, y1 + row_h), ref, f_body, align="left")
        y += row_h * len(rows)
    elif table_style == "TABLE_04":
        # Group table: 项目 | 结果 | 单位 | 参考范围
        for idx, (item, method, val, unit, ref) in enumerate(rows, 1):
            y1 = y + (idx - 1) * row_h
            draw.line([left, y1, W - right, y1], fill=(0, 0, 0), width=1)
            _text(draw, (xs[0] + 6, y1, xs[1] - 6, y1 + row_h), item, f_body, align="left")
            _text(draw, (xs[1] + 6, y1, xs[2] - 6, y1 + row_h), val, f_body, align="right")
            _text(draw, (xs[2] + 6, y1, xs[3] - 6, y1 + row_h), unit, f_body, align="left")
            _text(draw, (xs[3] + 6, y1, W - right - 6, y1 + row_h), ref, f_body, align="left")
        y += row_h * len(rows)
        draw.line([left, y, W - right, y], fill=(0, 0, 0), width=1)
    elif table_style == "TABLE_05":
        # Two-column list: left names, right results with units; separate rows and a center divider
        center_x = xs[1]
        draw.line([center_x, y - 6, center_x, y + row_h * len(rows) + 6], fill=(0, 0, 0), width=1)
        for idx, (item, method, val, unit, ref) in enumerate(rows, 1):
            y1 = y + (idx - 1) * row_h
            draw.line([left, y1, W - right, y1], fill=(0, 0, 0), width=1)
            _text(draw, (left + 8, y1, center_x - 8, y1 + row_h), item, f_body, align="left")
            _text(draw, (center_x + 8, y1, W - right - 8, y1 + row_h), f"{val}  {unit}  ({ref})", f_body, align="right")
        y += row_h * len(rows)

    # Outer box
    draw_outer = cfg.get("draw_outer_box", True)
    if table_style == "TABLE_03":
        draw_outer = True
    if draw_outer and table_style in ("TABLE_01", "TABLE_02", "TABLE_03"):
        top_y = y - row_h * len(rows) - header_h
        draw.rectangle([left, top_y - 2, W - right, y + 2], outline=(0, 0, 0), width=1)
    return y


def _draw_notes_and_footer(draw: ImageDraw.ImageDraw, page: Dict[str, Any], y: int, content: Dict[str, Any], schema: Dict[str, Any], fonts: Dict[str, ImageFont.FreeTypeFont]) -> int:
    W, H = page["size"]
    left, top, right, bottom = page["margins"]
    # Notes
    f_note = fonts["small"]
    # 不在默认值里带“备注：”，并统一移除传入内容中可能已经包含的“备注：/建议：”等前缀（可能重复多次），避免出现“备注：备注：”
    note_text = content.get("advice") or "报告结果仅供临床参考。"
    try:
        import re
        # 去除开头可能出现的多个“备注：/建议：”前缀，只保留正文
        note_text_clean = re.sub(r"^((备注|建议)[:：]\s*)+", "", str(note_text))
    except Exception:
        note_text_clean = str(note_text)
    _text(draw, (left, y + 16, W - right, y + 40), f"备注：{note_text_clean}", f_note, align="left")
    y += 64
    # Footer variants
    f_foot = fonts["small"]
    footer_style = schema.get("footer_style", "FOOTER_01")
    if footer_style == "FOOTER_01":
        _text(draw, (left, H - bottom - 40, left + 420, H - bottom - 20), f"检验时间：{content.get('exam_date','')}", f_foot, align="left")
        _text(draw, (left + 420, H - bottom - 40, left + 820, H - bottom - 20), f"报告时间：{content.get('exam_date','')}", f_foot, align="left")
        _text(draw, (W - right - 360, H - bottom - 40, W - right, H - bottom - 20), f"检验者：{content.get('doctor','')}    审核者：", f_foot, align="right")
    elif footer_style == "FOOTER_02":
        _text(draw, (left, H - bottom - 32, left + 300, H - bottom - 12), f"地址：{content.get('address','')}", f_foot, align="left")
        _text(draw, (left + 300, H - bottom - 32, left + 600, H - bottom - 12), f"电话：{content.get('phone','')}", f_foot, align="center")
        _text(draw, (W - right - 160, H - bottom - 32, W - right, H - bottom - 12), f"第1页", f_foot, align="right")
    elif footer_style == "FOOTER_03":
        _text(draw, (left, H - bottom - 28, left + 420, H - bottom - 10), f"检验者：{content.get('doctor','')}    审核者：", f_foot, align="left")
    return y
    return y


def generate_report(content: Dict[str, Any], layout: Any, output_path: str, config: Dict[str, Any]) -> str:
    """
    Render a report by decoupled layout engine.
    content: dict of values, must include at least hospital, report_type, name, gender, age, department, patient_id, doctor, exam_date, plus lab items for lab layout.
    layout: schema name from layouts.list_layouts(). For now focuses on hospital_lab_* schemas.
    output_path: target JPEG path.
    config: font_path, jpeg quality, etc.
    Returns the saved path.
    """
    registry = list_layouts()
    if isinstance(layout, dict):
        schema = layout
    else:
        if layout not in registry:
            raise ValueError(f"Unknown layout: {layout}. Available: {', '.join(registry.keys())}")
        schema = registry[layout]
    page = schema["page"]
    W, H = page["size"]
    img = Image.new("RGB", (W, H), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    y = page["margins"][1]
    # Prepare fonts according to schema font_style and density
    font_style = schema.get("font_style", "FONT_02")
    density = schema.get("density", "DENSITY_MEDIUM")
    fpaths = _choose_font_paths(font_style, config)
    sizes = _size_profile(density)
    fonts = {
        "hosp": _load_font(fpaths["title"], sizes["hosp"]),
        "title": _load_font(fpaths["header"], sizes["title"]),
        "header": _load_font(fpaths["header"], sizes["header"]),
        "body": _load_font(fpaths["body"], sizes["body"]),
        "small": _load_font(fpaths["small"], sizes["small"]),
    }

    # Header
    y = _draw_header(draw, page, schema, content, fonts, y, skip_logo=bool(config.get("skip_logo", True)))
    # Patient info: respect schema patient_layout
    page_with_patient = dict(page)
    page_with_patient["patient_layout"] = schema.get("patient_layout", "PATIENT_01")
    y = _draw_patient_info(draw, page_with_patient, y, content, fonts)
    y += 10
    # Table (if lab)
    if content.get("report_type") == "化验_检测报告":
        # Apply density tweak to table metrics
        cfg = schema["components"].get("lab_table", {})
        header_h = cfg.get("header_height", 44) + _size_profile(density)["row_delta"]
        row_h = cfg.get("row_height", 40) + _size_profile(density)["row_delta"]
        # Temporarily inject adjusted heights into page for use in drawing function
        page = dict(page)
        page["_header_h"] = max(28, header_h)
        page["_row_h"] = max(24, row_h)
        y = _draw_lab_table(draw, page, y, content, schema, fonts)
    else:
        # For other report types, basic placeholder blocks showing core lines (black text only)
        f_body = fonts["body"]
        for k in ["diagnosis", "impression", "recommendation", "treatment"]:
            v = content.get(k)
            if v:
                box = (page["margins"][0], y, W - page["margins"][2], y + 28)
                _text(draw, box, f"{k}：{v}", f_body, align="left")
                y += 30
    # Notes & footer
    _draw_notes_and_footer(draw, page, y, content, schema, fonts)

    # Save
    quality = int(config.get("jpeg_quality", 95))
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, format="JPEG", quality=quality, optimize=True)
    return output_path


def list_available_layouts() -> List[str]:
    return list(list_layouts().keys())
