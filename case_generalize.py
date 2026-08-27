"""
病例数据泛化工具

支持多种报告类型：
  - 影像文字报告
  - 化验_检测报告
  - 医嘱_处方
  - 门诊病历_就诊记录

用法:
  python case_generalize.py --type <报告类型> --output <输出目录> --num <数量>
"""

import os
import json
import random
import string
import argparse
import shutil
from datetime import datetime, timedelta

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageEnhance, ImageFilter

from report_types import get_report_type, list_report_types


# ============================================================
# 医院信息库（从 logo 目录动态加载，自动兼容“医院名称.*”的命名）
# ============================================================

def _load_hospitals():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    logo_dir = os.path.join(script_dir, "logo")
    loaded = []
    if os.path.isdir(logo_dir):
        for fname in os.listdir(logo_dir):
            lower = fname.lower()
            if lower.endswith(".png") or lower.endswith(".jpg") or lower.endswith(".jpeg"):
                name = os.path.splitext(fname)[0]
                loaded.append({"name": name, "logo": fname})
    # 如果目录为空，回退到内置列表（保证兼容以前的命名）
    if not loaded:
        return [
            {"name": "上海瑞宁医院", "logo": "上海瑞宁医院Ruining Hospital Shanghai.png"},
            {"name": "上海越明医疗中心", "logo": "上海越明医疗中心Yueming Medical Center Shanghai.png"},
            {"name": "北京安禾妇儿医院", "logo": "北京安禾妇儿医院Anhe Women & Children's Hospital Bejing.png"},
            {"name": "南京启康医院", "logo": "南京启康医院Qikang Hospital Nanjing.png"},
            {"name": "南京青岚医院", "logo": "南京青岚医院Qinglan Hospital Nanjing.png"},
            {"name": "天津清和医院", "logo": "天津清和医院Qinghe Hospital Tianjin.png"},
            {"name": "广州和煦医院", "logo": "广州和煦医院Hexu Hospital Guangzhou.png"},
            {"name": "广州润心医疗中心", "logo": "广州润心医疗中心Runxin Healthcare Guangzhou.png"},
            {"name": "成都柏安医院", "logo": "成都柏安医院Boan Hospital Chengdu.png"},
            {"name": "成都森澜医疗", "logo": "成都森澜医疗Senlan Medical Chengdu.png"},
            {"name": "杭州合悦健康中心", "logo": "杭州合悦健康中心Heyue Health Center Hangzhou.png"},
            {"name": "杭州明澈医院", "logo": "杭州明澈医院Mingche Hospital Hangzhou.png"},
            {"name": "杭州星合医院", "logo": "杭州星合医院Xinghe Hospital Hangzhou.png"},
            {"name": "武汉康礼医疗中心", "logo": "武汉康礼医疗中心Kangli Medical Center Wuhan.png"},
            {"name": "武汉济川医院", "logo": "武汉济川医院Jichuan Hospital Wuhan.png"},
            {"name": "深圳予安健康中心", "logo": "深圳予安健康中心Yuan Health Center Shenzhen.png"},
            {"name": "深圳景和医疗中心", "logo": "深圳景和医疗中心Jinghe Healthcare Shenzhen.png"},
            {"name": "苏州云舒健康中心", "logo": "苏州云舒健康中心Yunshu Health Center Suzhou.png"},
            {"name": "苏州澜汐医院", "logo": "苏州澜汐医院Lanxi Hospital Suzhou.png"},
            {"name": "西安达济医院", "logo": "西安达济医院Daji Hospital Xi'an.png"},
            {"name": "长沙连心医院", "logo": "长沙连心医院Lianxin Hospital Changsha.png"},
        ]
    return loaded

HOSPITALS = _load_hospitals()

DEPARTMENTS = ["妇科", "产科", "生殖科", "内分泌科", "妇产科", "体检科"]
DIAGNOSES = ["多囊卵巢综合征", "月经不调", "不孕症", "子宫肌瘤", "卵巢囊肿", "盆腔炎", "先兆流产", "更年期综合征", "乳腺增生", "宫颈炎"]


# ============================================================
# 基础工具
# ============================================================

def random_string(length=6):
    chars = string.ascii_uppercase + string.digits
    return ''.join(random.choice(chars) for _ in range(length))


def random_patient_id(prefix="HHM"):
    return prefix + ''.join(random.choice(string.digits) for _ in range(6))


def random_date(start_year=2024, end_year=2026):
    start = datetime(start_year, 1, 1)
    end = datetime(end_year, 12, 31)
    delta = end - start
    random_days = random.randint(0, delta.days)
    date = start + timedelta(days=random_days)
    return date.strftime("%Y-%m-%d")


def random_age(min_age=18, max_age=60):
    return random.randint(min_age, max_age)


def random_name():
    surnames = [
        "张", "李", "王", "刘", "陈",
        "杨", "黄", "赵", "周", "吴",
        "徐", "孙", "胡", "朱", "高"
    ]
    names = [
        "欣", "怡", "婷", "佳", "妍",
        "静", "倩", "雯", "颖", "娜",
        "悦", "琳", "璇", "菲", "敏"
    ]
    surname = random.choice(surnames)
    if random.random() < 0.7:
        return surname + random.choice(names)
    else:
        return surname + random.choice(names) + random.choice(names)


# ============================================================
# 字体
# ============================================================

def load_font(font_path, font_size):
    if not os.path.exists(font_path):
        raise FileNotFoundError(
            f"字体不存在: {font_path}\n请在 config 中设置正确的中文字体路径。"
        )
    return ImageFont.truetype(font_path, font_size)


# ============================================================
# 自动缩小字体以适应区域
# ============================================================

def fit_font(draw, text, font_path, max_width, max_height, start_size):
    size = start_size
    while size > 8:
        font = load_font(font_path, size)
        bbox = draw.textbbox((0, 0), text, font=font)
        width = bbox[2] - bbox[0]
        height = bbox[3] - bbox[1]
        if width <= max_width and height <= max_height:
            return font
        size -= 1
    return load_font(font_path, 8)


# ============================================================
# OpenCV 修复背景
# ============================================================

def inpaint_region(image, bbox):
    x1, y1, x2, y2 = bbox
    mask = np.zeros((image.shape[0], image.shape[1]), dtype=np.uint8)
    mask[y1:y2, x1:x2] = 255
    result = cv2.inpaint(image, mask, 3, cv2.INPAINT_TELEA)
    return result


# ============================================================
# 替换图片中的字段
# ============================================================

def replace_text(
    image,
    bbox,
    text,
    font_path,
    font_size=24,
    color=(0, 0, 0),
    method="sample",
    align="left"
):
    x1, y1, x2, y2 = bbox

    # 先按方法清底（默认sample：邻近底色100%实心填充）
    draw = ImageDraw.Draw(image)
    if method == "white":
        draw.rectangle([x1, y1, x2, y2], fill=(255, 255, 255))
    elif method == "gray":
        draw.rectangle([x1, y1, x2, y2], fill=(245, 245, 245))
    elif method == "sample":
        sample_h = max(2, (y2 - y1) // 8)
        band = image.crop((x1, max(0, y1 - sample_h), x2, y1))
        if band.size[0] and band.size[1]:
            avg = tuple(int(v) for v in np.array(band).reshape(-1, 3).mean(axis=0))
        else:
            band = image.crop((max(0, x1 - 4), y1, x1, y2))
            avg = tuple(int(v) for v in np.array(band).reshape(-1, 3).mean(axis=0)) if band.size[0] and band.size[1] else (255, 255, 255)
        draw.rectangle([x1, y1, x2, y2], fill=avg)
    elif method == "inpaint":
        try:
            cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
            cv_image = inpaint_region(cv_image, bbox)
            image = Image.fromarray(cv2.cvtColor(cv_image, cv2.COLOR_BGR2RGB))
            draw = ImageDraw.Draw(image)
        except Exception:
            draw.rectangle([x1, y1, x2, y2], fill=(255, 255, 255))
    elif method == "none":
        # 不进行任何清底，直接在当前背景上绘制（用于先铺背景面板后写字，避免再次覆盖造成色块拼接）
        pass

    max_width = x2 - x1
    max_height = y2 - y1

    font = fit_font(draw, text, font_path, max_width, max_height, font_size)

    bbox_text = draw.textbbox((0, 0), text, font=font)
    text_width = bbox_text[2] - bbox_text[0]
    text_height = bbox_text[3] - bbox_text[1]

    # 对齐方式：left/center/right
    if align == "right":
        tx = max(x1 + 1, x2 - text_width - 1)
    elif align == "center":
        tx = x1 + (max_width - text_width) / 2
    else:
        # 左对齐，稍微向右缩进 1px，避免贴边
        tx = x1 + 1
    ty = y1 + (max_height - text_height) / 2

    draw.text((tx, ty), text, font=font, fill=color)

    return image


def replace_logo(image, logo_path, logo_bbox=None, clean_mode="safe", clean_pad=6):
    """
    将 logo 粘贴到指定区域，要求100%覆盖原有医院名/标识：
    - 自动检测右上角旧院名区域，取与目标框的并集作为清理框
    - 清理框用“邻近底色均值”进行实心填充（不做 inpaint、不做模糊），确保不透底
    - logo 在框内留边距、等比缩放、居中粘贴；粘贴前在小框处再铺同色背板，避免半透明透底
    """
    if not os.path.exists(logo_path):
        print(f"[WARNING] Logo 文件不存在: {logo_path}")
        return image

    # 默认放在右上角区域（相对坐标），以防未传入 bbox
    if logo_bbox is None:
        W, H = image.size
        # 右上角 240x90 的盒子，距离右边 24px，顶部 20px
        logo_bbox = [max(W - 264, 0), 20, max(W - 24, 0), 110]

    x1, y1, x2, y2 = logo_bbox

    # 计算清理区域（默认严格：仅在给定 logo 框内；可选 safe/detect）
    if clean_mode == "safe":
        W, H = image.size
        pad = int(clean_pad) if isinstance(clean_pad, (int, float)) else 0
        clean_bbox = [max(0, x1 - pad), max(0, y1 - pad), min(W, x2 + pad), min(H, y2 + pad)]
    elif clean_mode == "detect":
        try:
            W, H = image.size
            search = (int(W * 0.2), 0, W, int(H * 0.28))
            crop = image.crop(search).convert("L")
            arr = np.array(crop)
            _, bw = cv2.threshold(arr, 240, 255, cv2.THRESH_BINARY_INV)
            bw = cv2.morphologyEx(bw, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8), iterations=2)
            contours, _ = cv2.findContours(bw, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if contours:
                cnt = max(contours, key=cv2.contourArea)
                dx, dy, dw, dh = cv2.boundingRect(cnt)
                cx1 = max(0, search[0] + dx - 8)
                cy1 = max(0, search[1] + dy - 8)
                cx2 = min(W, search[0] + dx + dw + 8)
                cy2 = min(H, search[1] + dy + dh + 16)
                clean_bbox = [min(x1, cx1), min(y1, cy1), max(x2, cx2), max(y2, cy2)]
            else:
                clean_bbox = [x1, y1, x2, y2]
        except Exception:
            clean_bbox = [x1, y1, x2, y2]
    else:
        clean_bbox = [x1, y1, x2, y2]

    # 1) 用邻近底色“实心填充”清理区域（不做 inpaint、不做模糊，保证100%覆盖）
    draw_clear = ImageDraw.Draw(image)
    try:
        sample_band = image.crop((clean_bbox[0], max(0, clean_bbox[1]-4), clean_bbox[2], clean_bbox[1]))
        if sample_band.size[0] and sample_band.size[1]:
            avg = tuple(int(v) for v in np.array(sample_band).reshape(-1, 3).mean(axis=0))
        else:
            # 退化：从清理框右侧采样
            band2 = image.crop((clean_bbox[2], clean_bbox[1], min(image.size[0], clean_bbox[2]+6), clean_bbox[3]))
            avg = tuple(int(v) for v in np.array(band2).reshape(-1, 3).mean(axis=0)) if band2.size[0] and band2.size[1] else (255, 255, 255)
    except Exception:
        avg = (255, 255, 255)
    draw_clear.rectangle(clean_bbox, fill=avg)

    # 2) 读取并准备 logo
    logo = Image.open(logo_path)
    if logo.mode != "RGBA":
        # 若无透明通道，假定白底，转为带 alpha 的 RGBA
        rgb = logo.convert("RGB")
        alpha = Image.new("L", rgb.size, 255)
        logo = Image.merge("RGBA", (*rgb.split(), alpha))
    else:
        logo = logo.convert("RGBA")

    target_w = max(1, x2 - x1)
    target_h = max(1, y2 - y1)

    # 自动留边距（防止贴边显得拥挤）
    margin = max(4, min(target_w, target_h) // 10)
    inner_w = max(1, target_w - 2 * margin)
    inner_h = max(1, target_h - 2 * margin)

    # 等比缩放
    logo_w, logo_h = logo.size
    ratio = min(inner_w / logo_w, inner_h / logo_h)
    new_w = max(1, int(round(logo_w * ratio)))
    new_h = max(1, int(round(logo_h * ratio)))
    logo = logo.resize((new_w, new_h), Image.Resampling.LANCZOS)

    # 居中偏移
    offset_x = x1 + (target_w - new_w) // 2
    offset_y = y1 + (target_h - new_h) // 2

    # 3) 在粘贴区域铺一层不透明的“背板”（纯白），防止半透明 logo 下透出旧文字；
    #    同时在目标框四周各扩 1px 再覆盖一层，减少边缘拼接痕迹。
    draw = ImageDraw.Draw(image)
    # 直接使用纯白背板，避免采样色与背景不一致产生边框
    avg = (255, 255, 255)
    back_x1 = max(0, offset_x - 2)
    back_y1 = max(0, offset_y - 2)
    back_x2 = min(image.size[0], offset_x + new_w + 2)
    back_y2 = min(image.size[1], offset_y + new_h + 2)
    draw.rectangle([back_x1, back_y1, back_x2, back_y2], fill=avg)
    # 额外一层轻微扩展覆盖，压暗线性插值造成的边缘锯齿
    pad2 = 1
    draw.rectangle([
        max(0, back_x1 - pad2), max(0, back_y1 - pad2),
        min(image.size[0], back_x2 + pad2), min(image.size[1], back_y2 + pad2)
    ], fill=avg)

    # 4) 将 logo 转换为完全不透明（去alpha），避免半透明区透出底色；再直接粘贴
    if logo.mode in ("RGBA", "LA"):
        bg = Image.new("RGBA", logo.size, (255, 255, 255, 255))
        bg.alpha_composite(logo)
        logo_opaque = bg.convert("RGB")
    else:
        logo_opaque = logo.convert("RGB")
    image.paste(logo_opaque, (offset_x, offset_y))

    # 5) 细边缘羽化：对背板边缘做一次极轻微的周边采样填充，进一步减轻拼接感
    try:
        bleed = 1
        _fill_rect_with_sampled_color = None  # 占位避免未引用警告
        band_top = (back_x1, max(0, back_y1 - bleed), back_x2, back_y1)
        band_bottom = (back_x1, back_y2, back_x2, min(image.size[1], back_y2 + bleed))
        band_left = (max(0, back_x1 - bleed), back_y1, back_x1, back_y2)
        band_right = (back_x2, back_y1, min(image.size[0], back_x2 + bleed), back_y2)
        # 取相邻带的均值涂抹到背板外一圈像素
        def _avg(crop_box):
            c = image.crop(crop_box)
            import numpy as _np
            arr = _np.array(c)
            return tuple(int(v) for v in arr.reshape(-1, 3).mean(axis=0)) if arr.size else avg
        edge_color = _avg((back_x1, max(0, back_y1 - 2), back_x2, back_y1))
        from PIL import ImageDraw as _ImageDraw
        d2 = _ImageDraw.Draw(image)
        d2.rectangle([max(0, back_x1-1), max(0, back_y1-1), back_x2+1, back_y1], fill=edge_color)
        d2.rectangle([max(0, back_x1-1), back_y2, back_x2+1, min(image.size[1], back_y2+1)], fill=edge_color)
        d2.rectangle([max(0, back_x1-1), back_y1, back_x1, back_y2], fill=edge_color)
        d2.rectangle([back_x2, back_y1, min(image.size[0], back_x2+1), back_y2], fill=edge_color)
    except Exception:
        pass

    return image

    return image


# ============================================================
# 图片增强
# ============================================================

def augment_image(image, config):
    rotate_range = config.get("rotation_range", [-1.0, 1.0])
    angle = random.uniform(rotate_range[0], rotate_range[1])
    image = image.rotate(
        angle,
        resample=Image.Resampling.BICUBIC,
        expand=False,
        fillcolor=(255, 255, 255)
    )

    brightness_range = config.get("brightness_range", [0.95, 1.05])
    brightness = random.uniform(brightness_range[0], brightness_range[1])
    image = ImageEnhance.Brightness(image).enhance(brightness)

    contrast_range = config.get("contrast_range", [0.95, 1.05])
    contrast = random.uniform(contrast_range[0], contrast_range[1])
    image = ImageEnhance.Contrast(image).enhance(contrast)

    if random.random() < config.get("blur_probability", 0.2):
        radius = random.uniform(0.2, 0.8)
        image = image.filter(ImageFilter.GaussianBlur(radius))

    if random.random() < config.get("noise_probability", 0.2):
        arr = np.array(image).astype(np.float32)
        noise = np.random.normal(0, config.get("noise_std", 3), arr.shape)
        arr += noise
        arr = np.clip(arr, 0, 255).astype(np.uint8)
        image = Image.fromarray(arr)

    return image


# ============================================================
# JPEG 压缩
# ============================================================

def save_with_compression(image, output_path, quality=95):
    image.save(output_path, format="JPEG", quality=quality, optimize=True)


def draw_prescription_mobile_shell(image):
    """绘制医嘱_处方的移动端病历页骨架。

    sample_input 是手机小程序样式：顶部导航 + tab + 蓝色分区标题 + 白色处方卡。
    如果只做文字替换，会显得像空白处方笺；这里用固定 UI 骨架保证信息层级和布局稳定。
    """
    W, H = image.size
    draw = ImageDraw.Draw(image)

    bg = (247, 248, 248)
    white = (255, 255, 255)
    cyan = (211, 246, 250)
    card_border = (224, 224, 224)
    divider = (232, 232, 232)
    label_divider = (226, 226, 226)

    # 页面基础：顶部白色，主体浅灰，模拟手机截屏。
    draw.rectangle([0, 0, W, H], fill=bg)
    draw.rectangle([0, 0, W, 280], fill=white)
    draw.rectangle([0, 280, W, 455], fill=white)

    # 顶部右侧小程序胶囊按钮。
    draw.rounded_rectangle([895, 145, 1230, 255], radius=55, fill=(248, 248, 248), outline=(232, 232, 232), width=1)
    draw.line([1063, 168, 1063, 232], fill=(225, 225, 225), width=1)

    # Tab 底部淡蓝选中条。
    draw.rectangle([258, 378, 370, 408], fill=(203, 245, 250))
    draw.line([50, 454, W - 50, 454], fill=(238, 238, 238), width=2)

    # 治疗计划 section：蓝色圆角标题 + 白色圆角内容卡。
    draw.rounded_rectangle([50, 480, W - 50, 790], radius=42, fill=cyan)
    draw.rounded_rectangle([50, 610, W - 50, 790], radius=38, fill=white, outline=card_border, width=2)
    draw.line([92, 640, W - 92, 640], fill=(242, 242, 242), width=2)

    # 处方 section：一个蓝色处方区域内放三张完整白色药品卡。
    # 这样既保留原图“处方卡片”的层级，也能满足三个药槽全部可读。
    draw.rounded_rectangle([50, 827, W - 50, 2715], radius=42, fill=cyan)

    # 患者/诊断信息栏：和药品明细分开，视觉上更像病例信息区。
    draw.rounded_rectangle([82, 905, W - 82, 1002], radius=24, fill=white, outline=card_border, width=2)
    draw.line([106, 955, W - 106, 955], fill=divider, width=2)

    # 药品卡片及内部表格分割线。
    cards = [
        [50, 1010, W - 50, 1515],
        [50, 1548, W - 50, 2106],
        [50, 2139, W - 50, 2697],
    ]
    row_lines = [
        [1122, 1222, 1308, 1394],
        [1712, 1812, 1898, 1984],
        [2302, 2402, 2488],
    ]
    for card, lines in zip(cards, row_lines):
        x1, y1, x2, y2 = card
        draw.rounded_rectangle(card, radius=34, fill=white, outline=card_border, width=3)
        # 标题行下方分割线 + 明细行分割线。
        for y in lines:
            draw.line([x1 + 38, y, x2 - 38, y], fill=divider, width=2)
        # 左侧标签列分割线，形成“字段名 / 内容”的病例表单感。
        draw.line([250, y1 + 118, 250, y2 - 36], fill=label_divider, width=2)
        # 标题行左侧小色条，增强处方条目的层级。
        draw.rounded_rectangle([86, y1 + 40, 94, y1 + 96], radius=4, fill=(123, 218, 228))

    # 底部医生/审核区域分割线。
    draw.line([90, 2588, W - 190, 2588], fill=divider, width=2)

    # 右下角审核悬浮按钮，保留原图“浮层”感，但改成固定审核人文案。
    draw.ellipse([1085, 2590, 1222, 2727], fill=white, outline=(235, 235, 235), width=1)
    draw.rectangle([1122, 2628, 1188, 2690], fill=(229, 247, 249))

    return image


# ============================================================
# 根据模板生成最终文字
# ============================================================

def render_value(template, data):
    """安全地渲染模板，缺失变量使用空字符串"""
    try:
        class SafeDict(dict):
            def __missing__(self, key):
                return ""  # 缺失的变量返回空字符串
        safe_data = SafeDict(data)
        return template.format_map(safe_data)
    except Exception as e:
        print(f"[WARNING] 模板渲染失败: {e}, template={template[:50]}")
        return template


def draw_imaging_report_shell(image):
    """重绘影像文字报告基础版式：白底报告壳 + 逻辑分区，避免原模板覆盖痕迹。"""
    draw = ImageDraw.Draw(image)
    W, H = image.size
    white = (255, 255, 255)
    title_blue = (28, 88, 145)
    text_blue = (45, 88, 130)
    line = (150, 162, 174)
    light_line = (214, 220, 226)
    pale_fill = (247, 250, 253)
    section_fill = (238, 245, 252)

    draw.rectangle([0, 0, W, H], fill=white)

    # 顶部留出右上角 logo 区域，左侧由字段写医院/报告标题。
    draw.line([56, 132, W - 56, 132], fill=title_blue, width=3)
    draw.line([56, 185, W - 56, 185], fill=light_line, width=1)

    # 患者/检查信息栏。
    info_box = [56, 210, W - 56, 350]
    draw.rounded_rectangle(info_box, radius=8, fill=pale_fill, outline=light_line, width=1)
    draw.line([76, 280, W - 76, 280], fill=light_line, width=1)

    # 超声所见正文区域。
    body_box = [56, 405, W - 56, 1105]
    draw.rectangle([body_box[0], body_box[1], body_box[2], body_box[3]], fill=white, outline=line, width=2)
    draw.rectangle([body_box[0], body_box[1], body_box[2], body_box[1] + 54], fill=section_fill)
    draw.line([body_box[0], body_box[1] + 54, body_box[2], body_box[1] + 54], fill=line, width=2)
    # 从原始样本裁一块超声暗图区作为固定示意图，贴到白底报告壳内。
    # 注意：不是覆盖旧文字，而是把原图中的影像区域当作图片素材复用。
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        src_path = os.path.join(script_dir, "sample_input", "影像文字报告.jpg")
        with Image.open(src_path).convert("RGB") as src:
            ultrasound = src.crop((40, 460, 1180, 740))
        target_box = [76, 480, W - 76, 746]
        target_w = target_box[2] - target_box[0]
        target_h = target_box[3] - target_box[1]
        ultrasound = ultrasound.resize((target_w, target_h), Image.Resampling.LANCZOS)
        image.paste(ultrasound, (target_box[0], target_box[1]))
        draw.rectangle(target_box, outline=(120, 130, 140), width=2)
    except Exception:
        # 如果素材读取失败，保留一块灰框，生成流程不中断。
        target_box = [76, 480, W - 76, 746]
        draw.rectangle(target_box, fill=(28, 32, 36), outline=(120, 130, 140), width=2)

    # 内容区只画少量逻辑分隔，不按每个字段涂背景。
    for y in [770, 870, 970]:
        draw.line([body_box[0] + 20, y, body_box[2] - 20, y], fill=light_line, width=1)

    # 超声提示/建议区域。
    result_box = [56, 1140, W - 56, 1345]
    draw.rectangle(result_box, fill=white, outline=line, width=2)
    draw.rectangle([result_box[0], result_box[1], result_box[2], result_box[1] + 54], fill=section_fill)
    draw.line([result_box[0], result_box[1] + 54, result_box[2], result_box[1] + 54], fill=line, width=2)
    draw.line([result_box[0] + 20, 1242, result_box[2] - 20, 1242], fill=light_line, width=1)

    # 底部签名栏。
    footer_y = 1395
    draw.line([56, footer_y, W - 56, footer_y], fill=light_line, width=1)
    draw.line([56, footer_y + 92, W - 56, footer_y + 92], fill=light_line, width=1)

    return image


def draw_lab_report_shell(image):
    """重绘化验单基础版式：真实检验报告常见的页眉、患者信息栏和规整项目表。"""
    draw = ImageDraw.Draw(image)
    W, H = image.size
    white = (255, 255, 255)
    title_blue = (30, 96, 150)
    line = (160, 170, 180)
    light_line = (215, 220, 225)
    header_fill = (242, 247, 252)
    info_fill = (248, 251, 253)

    draw.rectangle([0, 0, W, H], fill=white)

    # 页眉区域：标题下只保留一条主线，避免无意义横线。
    draw.line([56, 104, W - 56, 104], fill=title_blue, width=3)
    draw.line([56, 182, W - 56, 182], fill=light_line, width=1)

    # 患者信息栏：两行信息，边框明确但不切碎内容。
    info_box = [56, 205, W - 56, 335]
    draw.rounded_rectangle(info_box, radius=8, fill=info_fill, outline=light_line, width=1)
    draw.line([76, 270, W - 76, 270], fill=light_line, width=1)

    # 检验项目表：固定列、固定行高，线条只服务表格结构。
    left, right = 56, W - 56
    top = 388
    header_h = 48
    row_h = 60
    rows = 13
    bottom = top + header_h + rows * row_h

    draw.rectangle([left, top, right, top + header_h], fill=header_fill)
    draw.rectangle([left, top, right, bottom], outline=line, width=2)

    # 列：序号、项目、缩写、结果、单位、参考范围
    cols = [left, 120, 430, 590, 745, 930, right]
    for x in cols[1:-1]:
        draw.line([x, top, x, bottom], fill=light_line, width=1)
    draw.line([left, top + header_h, right, top + header_h], fill=line, width=2)
    for i in range(1, rows + 1):
        y = top + header_h + i * row_h
        draw.line([left, y, right, y], fill=light_line, width=1)

    # 底部备注和签名区域。
    note_top = bottom + 30
    draw.rounded_rectangle([56, note_top, W - 56, note_top + 92], radius=8, fill=white, outline=light_line, width=1)
    draw.line([56, note_top + 120, W - 56, note_top + 120], fill=light_line, width=1)

    return image


# ============================================================
# 生成一个病例
# ============================================================

def generate_case(
    input_path,
    output_path,
    config,
    case_index,
    report_type,
    hospital_info,
    logo_bbox,
    truth_data,
    data
):
    image = Image.open(input_path).convert("RGB")
    layout_mode = config.get("layout", "default")
    if layout_mode == "default":
        if report_type == "医嘱_处方":
            image = draw_prescription_mobile_shell(image)
        elif report_type == "影像文字报告":
            image = draw_imaging_report_shell(image)
        elif report_type == "化验_检测报告":
            image = draw_lab_report_shell(image)
    else:
        # plain_horizontal: 仅清空整图为白底，随后按横板纯文字布局输出，不绘制任何底色/表格
        from PIL import ImageDraw
        W, H = image.size
        ImageDraw.Draw(image).rectangle([0, 0, W, H], fill=(255, 255, 255))

    # 使用传入的数据（不再重新生成，确保与 truth 一致）
    module = get_report_type(report_type)
    if layout_mode == "plain_horizontal":
        fields = build_plain_horizontal_fields(report_type, data)
    else:
        fields = module.get_fields()

    # 替换字段
    for field in fields:
        bbox = field["bbox"]
        template = field["template"]
        value = render_value(template, data)

        # 针对“门诊病历_就诊记录”减少色块拼接感：
        # 在需要的行先绘制统一宽度的浅灰面板，再直接在上面写字（method='none'），避免多次采样清底造成的色差边界。
        if layout_mode == "plain_horizontal":
            draw_method = "none"
        elif report_type == "门诊病历_就诊记录":
            # 门诊病历在 clean_base 中已经统一铺好了浅灰底，这里直接写字避免再次清底造成色块拼接
            draw_method = "none"
        elif report_type == "影像文字报告":
            # 影像报告改为白底重绘报告壳，所有文字直接写在空白/表单区域上，不再做原图采样覆盖。
            draw_method = "none"
        elif report_type == "化验_检测报告":
            # 化验单版式已整体重绘，字段直接落在表格单元格内，避免二次清底制造怪异色块/断线。
            draw_method = "none"
        else:
            draw_method = field.get("method", "sample")

        image = replace_text(
            image=image,
            bbox=bbox,
            text=value,
            font_path=config["font_path"],
            font_size=field.get("font_size", 24),
            color=tuple(field.get("color", [0, 0, 0])),
            method=draw_method,
            align=field.get("align", "left")
        )

    # Logo 替换（可通过 config.skip_logo 关闭） - 使用脚本所在目录
    if layout_mode != "plain_horizontal" and not config.get("skip_logo", False):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        logo_dir = os.path.join(script_dir, "logo")
        # 优先使用配置中的 logo 文件名
        preferred_logo = hospital_info.get("logo")
        candidate_paths = []
        if preferred_logo:
            candidate_paths.append(os.path.join(logo_dir, preferred_logo))
        # 兼容：如果 logo 文件以医院名称命名（不含后缀），尝试常见后缀
        hosp_name = hospital_info.get("name", "").strip()
        if hosp_name:
            for ext in (".png", ".jpg", ".jpeg"):
                candidate_paths.append(os.path.join(logo_dir, hosp_name + ext))

        logo_path = None
        for p in candidate_paths:
            if os.path.exists(p):
                logo_path = p
                break

        if logo_path and report_type != "医嘱_处方":
            image = replace_logo(image, logo_path, logo_bbox)
        elif report_type == "医嘱_处方":
            # 医嘱_处方样本是移动端病历/处方页面，右上角应保留小程序菜单胶囊，
            # 不贴医院 logo，否则会变成传统纸质处方笺，布局与 sample_input 不一致。
            pass
        else:
            print(f"[WARNING] 未找到匹配的 Logo 文件，已跳过。尝试过: {', '.join(candidate_paths)}")

    # 图片增强
    image = augment_image(image, config)

    # 保存
    quality = random.randint(
        config.get("jpeg_quality_min", 85),
        config.get("jpeg_quality_max", 100)
    )
    save_with_compression(image, output_path, quality)

    # 保存 truth JSON
    truth_path = output_path.replace(".jpg", ".json")
    with open(truth_path, "w", encoding="utf-8") as f:
        json.dump(truth_data, f, ensure_ascii=False, indent=2)

    return truth_data


def build_plain_horizontal_fields(report_type, data):
    """
    横板纯文字布局（不画底色/表格/面板），仅将已有文字信息以横向区块排列：
    - 顶部：医院全称 + 报告类型标题
    - 基本信息：姓名/性别/年龄/病历号/就诊或检查日期/科室/医生
    - 其余内容按原类型要点简洁展示
    统一在 A4-like 纵向图上按横条摆放，字段 bbox 跨整行，便于阅读。
    """
    # 统一版式参数
    # A4纵向 + 窄边距（左右各 ~36px，顶部~30px），高密度排版
    left = 36
    right = 1210
    y = 30
    gap = 34  # 行距较紧凑
    def row(name, text, size=22, color=(0, 0, 0), align="left", height=30):
        nonlocal y
        box = [left, y, right, y + height]
        y += max(gap, height)
        return {"name": name, "bbox": box, "template": text, "font_size": size, "color": list(color), "align": align}

    title_map = {
        "影像文字报告": "超声影像文字报告",
        "化验_检测报告": "检验报告单",
        "医嘱_处方": "处方",
        "门诊病历_就诊记录": "门诊病历",
    }

    fields = []
    # 顶部医院 + 标题
    # 顶部居中：医院名大号加粗风格（这里通过字号模拟加粗），下方小一号的报告类型
    fields.append(row("hospital", "{hospital}", size=30, align="center"))
    fields.append(row("title", title_map.get(report_type, report_type), size=22, align="center"))

    # 基础信息
    # 患者基本信息：横向多列（用较宽的行，字段间以空格分隔，模拟多列）
    fields.append(row("p_name", "患者姓名：{name}      性别：{gender}      年龄：{age}岁      科室：{department}", size=20))
    fields.append(row("p_ids", "门诊号：{patient_id}      申请医生：{doctor}", size=20))
    date_label = "检查日期" if report_type in ("影像文字报告", "化验_检测报告") else "就诊日期"
    fields.append(row("date", f"{date_label}：{{exam_date}}", size=20))
    y += 6  # 小间隙

    if report_type == "影像文字报告":
        # 关键所见与提示
        fields.append(row("findings1", "{right_ovary_line}", size=20))
        fields.append(row("findings2", "{left_ovary_line}", size=20))
        fields.append(row("findings3", "{pelvic_effusion_line}", size=20))
        fields.append(row("impression", "{impression_line}", size=20))
        fields.append(row("recommendation", "{recommendation_line}", size=20))
        y += 16
        # 底部小字
        fields.append(row("sign", "报告时间：{exam_date}      报告医师：{doctor}", size=18))
    elif report_type == "化验_检测报告":
        # 构建表头行，模拟传统LIS表格（仅使用文字行，不绘制格线，后续由绘制器加线）
        # 列含：序号、项目名称、方法、结果、单位、参考范围
        # 表头
        fields.append(row("tbl_header", "序号    项目名称                                   方法        结果      单位      参考范围", size=20))
        # 数据行（保持已有数值与字段）
        rows = [
            (1, "白细胞计数(WBC)", "自动", "{wbc}", "×10^9/L", "4-12"),
            (2, "红细胞计数(RBC)", "自动", "{rbc}", "×10^12/L", "4-6"),
            (3, "血红蛋白(HGB)", "比色", "{hgb}", "g/L", "110-180"),
            (4, "血小板计数(PLT)", "自动", "{plt}", "×10^9/L", "100-350"),
            (5, "谷丙转氨酶(ALT)", "速率法", "{alt}", "U/L", "5-45"),
            (6, "谷草转氨酶(AST)", "速率法", "{ast}", "U/L", "5-45"),
            (7, "空腹血糖(GLU)", "葡萄糖氧化酶法", "{glu}", "mmol/L", "3-8"),
            (8, "高密度脂蛋白(HDL)", "直接法", "{hdl}", "mmol/L", "0.8-2.0"),
            (9, "低密度脂蛋白(LDL)", "直接法", "{ldl}", "mmol/L", "2-4"),
        ]
        for no, item, method, val, unit, ref in rows:
            # 排列：序号(左)、项目(左)、方法(居中)、结果(右)、单位(左小字)、参考范围(左小字)
            fields.append(row(f"lab_{no}_row", f"{no:>2}    {item:<36}  {method:<10}  {val:>6}    {unit:<8}  {ref}", size=20))
        y += 12
        # 备注/说明区（2-4行）
        fields.append(row("note1", "备注：{advice}", size=18))
        # 底部签名/时间
        fields.append(row("footer1", "检验时间：{exam_date}      报告时间：{exam_date}", size=18))
        fields.append(row("footer2", "检验者：{doctor}      审核者：", size=18))
    elif report_type == "医嘱_处方":
        # 每种药一行，后续行给出用法/用量/疗程
        meds = [
            ("med1", "{med1_name} {med1_spec}"),
            ("med2", "{med2_name} {med2_spec}"),
            ("med3", "{med3_name} {med3_spec}"),
        ]
        for key, disp in meds:
            fields.append(row(f"{key}_line1", f"药品：{disp}", size=20))
            fields.append(row(f"{key}_line2", f"用法：{{{key}_usage}}    频次：{{{key}_freq}}", size=18))
            fields.append(row(f"{key}_line3", f"疗程：{{{key}_days}}    备注：{{{key}_instruction}}", size=18))
        y += 10
        fields.append(row("sign", "医生：{doctor}", size=18))
    elif report_type == "门诊病历_就诊记录":
        fields.append(row("vital", "体征：体温 {temp}℃    心率 {hr}次/分    血压 {bp}mmHg    呼吸 {rr}次/分", size=20))
        fields.append(row("symptoms", "主诉：{symptom1}、{symptom2}、{symptom3}", size=20))
        fields.append(row("history", "现病史：患者因{symptom1}、{symptom2}就诊，病程约{age}天。", size=20))
        fields.append(row("diagnosis", "诊断：{diagnosis}", size=20))
        fields.append(row("treatment", "处理：{treatment}", size=20))
        fields.append(row("advice", "建议：{advice}", size=20))
        fields.append(row("followup", "复诊：{followup_days}天后", size=20))

    return fields


# ============================================================
# 构建 Truth 数据
# ============================================================

def build_truth_data(report_type, hospital_info, data, filename):
    truth = {
        "doc_id": data.get("patient_id", ""),
        "hospital": hospital_info["name"],
        "department": data.get("department", "妇科"),
        "visit_date": data.get("exam_date", ""),
        "diagnosis_summary": data.get("diagnosis", data.get("impression", "")),
        "medical_advice": data.get("recommendation", data.get("advice", "")),
        "examinations": [],
        "medication_suggestions": [],
        # original_file_name 优先使用外部传入（例如原始PDF/图像名），否则回退为当前生成文件名
        "original_file_name": data.get("original_file_name", filename)
    }

    if report_type == "化验_检测报告":
        truth["examinations"] = [
            {"item_name": "白细胞计数", "value": str(data.get("wbc", "")), "unit": "×10^9/L", "reference_range": "4-12", "abnormal": False},
            {"item_name": "红细胞计数", "value": str(data.get("rbc", "")), "unit": "×10^12/L", "reference_range": "4-6", "abnormal": False},
            {"item_name": "血红蛋白", "value": str(data.get("hgb", "")), "unit": "g/L", "reference_range": "110-180", "abnormal": False},
            {"item_name": "血小板计数", "value": str(data.get("plt", "")), "unit": "×10^9/L", "reference_range": "100-350", "abnormal": False},
            {"item_name": "谷丙转氨酶", "value": str(data.get("alt", "")), "unit": "U/L", "reference_range": "5-45", "abnormal": False},
            {"item_name": "谷草转氨酶", "value": str(data.get("ast", "")), "unit": "U/L", "reference_range": "5-45", "abnormal": False},
            {"item_name": "总胆红素", "value": str(data.get("tbil", "")), "unit": "μmol/L", "reference_range": "3-25", "abnormal": False},
            {"item_name": "肌酐", "value": str(data.get("crea", "")), "unit": "μmol/L", "reference_range": "40-120", "abnormal": False},
            {"item_name": "空腹血糖", "value": str(data.get("glu", "")), "unit": "mmol/L", "reference_range": "3-8", "abnormal": False},
            {"item_name": "总胆固醇", "value": str(data.get("cho", "")), "unit": "mmol/L", "reference_range": "3-6", "abnormal": False},
            {"item_name": "甘油三酯", "value": str(data.get("tg", "")), "unit": "mmol/L", "reference_range": "0.5-2.5", "abnormal": False},
            {"item_name": "高密度脂蛋白", "value": str(data.get("hdl", "")), "unit": "mmol/L", "reference_range": "0.8-2.0", "abnormal": False},
            {"item_name": "低密度脂蛋白", "value": str(data.get("ldl", "")), "unit": "mmol/L", "reference_range": "2-4", "abnormal": False},
        ]

    elif report_type == "医嘱_处方":
        truth["medical_advice"] = data.get("treatment_plan", "")
        meds = []
        for i in range(1, 4):
            name = data.get(f"med{i}_name", "")
            if name:
                source_text = (
                    f"药品 {data.get(f'med{i}_display', name + ' ' + data.get(f'med{i}_spec', ''))} "
                    f"用法 {data.get(f'med{i}_usage', data.get('usage', ''))} {data.get(f'med{i}_form', '')} "
                    f"用量 {data.get(f'med{i}_dose', '')}，{data.get(f'med{i}_freq', '')} "
                    f"疗程 {data.get(f'med{i}_days', '')} 总量 {data.get(f'med{i}_total', '')}"
                ).strip()
                meds.append({
                    "drug_name": name,
                    "dosage": data.get(f"med{i}_spec", ""),
                    "frequency": data.get(f"med{i}_freq", ""),
                    "duration": data.get(f"med{i}_days", ""),
                    "instruction": data.get(f"med{i}_instruction", ""),
                    "source_text": source_text
                })
        truth["medication_suggestions"] = meds

    elif report_type == "门诊病历_就诊记录":
        truth["examinations"] = [
            {"item_name": "体温", "value": str(data.get("temp", "")), "unit": "℃", "reference_range": "36-37.5", "abnormal": data.get("temp", 37) > 37.5},
            {"item_name": "心率", "value": str(data.get("hr", "")), "unit": "次/分", "reference_range": "60-100", "abnormal": False},
            {"item_name": "血压", "value": data.get("bp", ""), "unit": "mmHg", "reference_range": "90-140/60-90", "abnormal": False},
        ]
        truth["medical_advice"] = data.get("advice", "")

    elif report_type == "影像文字报告":
        # 影像文字报告必须按完整字段行/完整句覆盖：涉及测量值的句子整体重写，
        # 句内数字由本次 data 统一生成，避免“旧句残留 + 新数字贴片”的错位问题。
        truth["diagnosis_summary"] = data.get("impression_line", data.get("impression", ""))
        truth["medical_advice"] = data.get("recommendation_line", data.get("recommendation", ""))
        truth["examinations"] = [
            {"item_name": "右卵巢", "value": f"{data.get('right_ovary_length', '')}*{data.get('right_ovary_width', '')}*{data.get('right_ovary_height', '')}", "unit": "mm", "reference_range": "25-40*15-25*20-35", "abnormal": False, "source_text": data.get("right_ovary_line", "")},
            {"item_name": "右侧基础卵泡", "value": str(data.get("follicle_count_right", "")), "unit": "个", "reference_range": "", "abnormal": False, "source_text": data.get("right_ovary_line", "")},
            {"item_name": "左卵巢", "value": f"{data.get('left_ovary_length', '')}*{data.get('left_ovary_width', '')}*{data.get('left_ovary_height', '')}", "unit": "mm", "reference_range": "25-40*15-25*20-35", "abnormal": False, "source_text": data.get("left_ovary_line", "")},
            {"item_name": "左侧基础卵泡", "value": str(data.get("follicle_count_left", "")), "unit": "个", "reference_range": "", "abnormal": False, "source_text": data.get("left_ovary_line", "")},
            {"item_name": "盆腔积液", "value": data.get("pelvic_effusion", ""), "unit": "", "reference_range": "无", "abnormal": data.get("pelvic_effusion", "无") != "无", "source_text": data.get("pelvic_effusion_line", "")},
        ]

    return truth


# ============================================================
# 主程序
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="病例数据泛化工具 - 支持多种报告类型",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
可用报告类型:
  {types}

示例:
  python case_generalize.py --type 影像文字报告 --output ./result --num 20
  python case_generalize.py --type 化验_检测报告 --output ./result --num 20
        """.format(types="\n  ".join(list_report_types()))
    )

    parser.add_argument("--type", required=True, choices=list_report_types(),
                        help="报告类型")
    parser.add_argument("--output", default="./result", help="输出目录")
    parser.add_argument("--num", type=int, default=20, help="生成数量")
    parser.add_argument("--font-path", help="字体路径")
    parser.add_argument("--logo-bbox", default="50,20,200,100",
                        help="Logo 替换区域 x1,y1,x2,y2")
    parser.add_argument("--no-logo", action="store_true", help="不在页面上贴医院Logo，仅在标题中展示医院全称")
    parser.add_argument("--layout", choices=["default", "plain_horizontal"], default="default",
                        help="版式：default=按原始模板壳渲染；plain_horizontal=横板纯文字，不铺底色/表格")
    parser.add_argument("--start", type=int, default=1, help="起始编号（用于病历号与文件名的顺序编号）")

    args = parser.parse_args()

    # 清空输出目录
    if os.path.exists(args.output):
        shutil.rmtree(args.output)
    os.makedirs(args.output, exist_ok=True)

    # 创建报告类型子目录
    report_dir = os.path.join(args.output, args.type)
    os.makedirs(report_dir, exist_ok=True)

    # 默认配置
    config = {
        "font_path": args.font_path or "C:\\Windows\\Fonts\\simkai.ttf",
        "rotation_range": [-1.0, 1.0],
        "brightness_range": [0.95, 1.05],
        "contrast_range": [0.95, 1.05],
        "blur_probability": 0.2,
        "noise_probability": 0.2,
        "noise_std": 3,
        "jpeg_quality_min": 85,
        "jpeg_quality_max": 100,
        "skip_logo": bool(args.no_logo),
        "layout": args.layout,
    }

    # Logo bbox
    try:
        logo_bbox = [int(x) for x in args.logo_bbox.split(",")]
    except ValueError:
        logo_bbox = [50, 20, 200, 100]

    # 获取输入图片路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_dir = os.path.join(script_dir, "sample_input")
    input_path = os.path.join(input_dir, f"{args.type}.jpg")

    if not os.path.exists(input_path):
        print(f"错误: 输入图片不存在: {input_path}")
        return

    # 生成病例（顺序编号，确保编号唯一且与文件名一致）
    start_index = args.start if args.start >= 1 else 1
    end_index = start_index + args.num - 1
    # 病历号前缀：按类型保持既有风格
    pid_prefix_map = {
        "影像文字报告": "P",
        "化验_检测报告": "LA",
        "医嘱_处方": "PR",
        "门诊病历_就诊记录": "MR",
    }

    import re
    def _hospital_cn(name: str) -> str:
        try:
            m = re.search(r"[A-Za-z]", name)
            return name[:m.start()].strip() if m else name.strip()
        except Exception:
            return name

    for i in range(start_index, end_index + 1):
        filename = f"case_{i:05d}.jpg"
        output_path = os.path.join(report_dir, filename)

        # 随机选择医院
        hospital_info = random.choice(HOSPITALS)

        name_full = hospital_info['name']
        hosp_cn = _hospital_cn(name_full)
        print(f"[{i}/{args.num}] Generating {args.type}/{filename} - {hosp_cn}")

        # 生成数据
        module = get_report_type(args.type)
        data = module.generate_data()
        data["department"] = random.choice(DEPARTMENTS)
        # 仅保留中文医院名（若原始包含英文并列展示）
        data["hospital"] = hosp_cn
        # 性别强制为女
        data["gender"] = "女"
        # 覆盖病历号，确保唯一且可追溯
        data["patient_id"] = f"{pid_prefix_map.get(args.type, 'ID')}{i:05d}"
        # 性别强制为女（各模块已是女，这里再次兜底）
        data["gender"] = "女"

        # 构建 truth
        truth = build_truth_data(args.type, hospital_info, data, filename)

        generate_case(
            input_path=input_path,
            output_path=output_path,
            config=config,
            case_index=i,
            report_type=args.type,
            hospital_info=hospital_info,
            logo_bbox=logo_bbox,
            truth_data=truth,
            data=data
        )

    print()
    print(f"完成！共生成 {args.num} 个 {args.type} 病例。")
    print(f"输出目录: {report_dir}")


if __name__ == "__main__":
    main()