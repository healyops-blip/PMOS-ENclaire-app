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
    method="sample"
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

    max_width = x2 - x1
    max_height = y2 - y1

    font = fit_font(draw, text, font_path, max_width, max_height, font_size)

    bbox_text = draw.textbbox((0, 0), text, font=font)
    text_width = bbox_text[2] - bbox_text[0]
    text_height = bbox_text[3] - bbox_text[1]

    # 默认左对齐，稍微向右缩进 1px，避免贴边
    tx = x1 + 1
    ty = y1 + (max_height - text_height) / 2

    draw.text((tx, ty), text, font=font, fill=color)

    return image


def replace_logo(image, logo_path, logo_bbox=None, clean_mode="none", clean_pad=0):
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

    # 3) 在粘贴区域铺一层不透明的“背板”（同色），防止半透明 logo 下透出旧文字
    draw = ImageDraw.Draw(image)
    # 采用上缘窄带的均值色作为背板颜色（偏白）
    sample = image.crop((x1, max(0, y1 - 4), x2, y1))
    if sample.size[0] and sample.size[1]:
        avg = tuple(int(v) for v in np.array(sample).reshape(-1, 3).mean(axis=0))
    else:
        avg = (255, 255, 255)
    back_x1 = max(0, offset_x - 2)
    back_y1 = max(0, offset_y - 2)
    back_x2 = min(image.size[0], offset_x + new_w + 2)
    back_y2 = min(image.size[1], offset_y + new_h + 2)
    draw.rectangle([back_x1, back_y1, back_x2, back_y2], fill=avg)

    # 4) 直接粘贴（不做任何模糊）
    image.paste(logo, (offset_x, offset_y), logo)

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

    # 使用传入的数据（不再重新生成，确保与 truth 一致）
    module = get_report_type(report_type)
    fields = module.get_fields()

    # 替换字段
    for field in fields:
        bbox = field["bbox"]
        template = field["template"]
        value = render_value(template, data)

        image = replace_text(
            image=image,
            bbox=bbox,
            text=value,
            font_path=config["font_path"],
            font_size=field.get("font_size", 24),
            color=tuple(field.get("color", [0, 0, 0])),
            method=field.get("method", "sample")
        )

    # Logo 替换 - 使用脚本所在目录
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

    if logo_path:
        image = replace_logo(image, logo_path, logo_bbox)
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
        meds = []
        for i in range(1, 4):
            name = data.get(f"med{i}_name", "")
            if name:
                meds.append({
                    "drug_name": name,
                    "dosage": data.get(f"med{i}_spec", ""),
                    "frequency": data.get(f"med{i}_freq", ""),
                    "duration": data.get(f"med{i}_days", ""),
                    "instruction": data.get(f"med{i}_freq", ""),
                    "source_text": f"{name} {data.get(f'med{i}_spec', '')} {data.get(f'med{i}_freq', '')} {data.get(f'med{i}_days', '')}"
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
        truth["examinations"] = [
            {"item_name": "右卵巢大小", "value": f"{data.get('right_ovary_length', '')}*{data.get('right_ovary_width', '')}*{data.get('right_ovary_height', '')}", "unit": "mm", "reference_range": "25-40*15-25*20-35", "abnormal": False},
            {"item_name": "左卵巢大小", "value": f"{data.get('left_ovary_length', '')}*{data.get('left_ovary_width', '')}*{data.get('left_ovary_height', '')}", "unit": "mm", "reference_range": "25-40*15-25*20-35", "abnormal": False},
            {"item_name": "盆腔积液", "value": data.get("pelvic_effusion", ""), "unit": "", "reference_range": "无", "abnormal": data.get("pelvic_effusion", "无") != "无"},
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
        "jpeg_quality_max": 100
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

    # 生成病例
    for i in range(1, args.num + 1):
        filename = f"case_{i:05d}.jpg"
        output_path = os.path.join(report_dir, filename)

        # 随机选择医院
        hospital_info = random.choice(HOSPITALS)

        print(f"[{i}/{args.num}] Generating {args.type}/{filename} - {hospital_info['name']}")

        # 生成数据
        module = get_report_type(args.type)
        data = module.generate_data()
        data["department"] = random.choice(DEPARTMENTS)

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