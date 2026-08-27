import os
import cv2
import numpy as np
from PIL import Image, ImageDraw
from report_types import get_report_type


def _compute_clean_logo_union_bbox(image, logo_bbox):
    x1, y1, x2, y2 = logo_bbox
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
            cx, cy, cw, ch = cv2.boundingRect(cnt)
            cb = [
                max(0, search[0] + cx - 8),
                max(0, search[1] + cy - 8),
                min(W, search[0] + cx + cw + 8),
                min(H, search[1] + cy + ch + 16),
            ]
            return [min(x1, cb[0]), min(y1, cb[1]), max(x2, cb[2]), max(y2, cb[3])]
    except Exception:
        pass
    return [x1, y1, x2, y2]


def _fill_rect_with_sampled_color(image, rect, fallback=(255, 255, 255)):
    x1, y1, x2, y2 = rect
    draw = ImageDraw.Draw(image)
    try:
        band = image.crop((x1, max(0, y1 - 4), x2, y1))
        if band.size[0] and band.size[1]:
            avg = tuple(int(v) for v in np.array(band).reshape(-1, 3).mean(axis=0))
        else:
            band = image.crop((x2, y1, min(image.size[0], x2 + 6), y2))
            avg = tuple(int(v) for v in np.array(band).reshape(-1, 3).mean(axis=0)) if band.size[0] and band.size[1] else fallback
    except Exception:
        avg = fallback
    draw.rectangle(rect, fill=avg)
    return image


def build_clean_base_image(input_path, report_type, logo_bbox, fill_mode="sample", logo_clean_mode="safe", logo_clean_pad=6):
    """
    生成“干净底图”：
    - 清除右上角院名/Logo（扩大检测并集），按 fill_mode 填充
    - 清除所有字段 bbox，按 fill_mode 填充
    返回 PIL.Image 对象
    """
    image = Image.open(input_path).convert("RGB")
    # 1) 清理 logo 区域
    # 选用清理策略：safe=仅扩展 logo 框；detect=检测并集；none=仅 logo 框
    if logo_clean_mode == "detect":
        clean_bbox = _compute_clean_logo_union_bbox(image, logo_bbox)
    elif logo_clean_mode == "none":
        clean_bbox = list(logo_bbox)
    else:  # safe
        x1, y1, x2, y2 = logo_bbox
        W, H = image.size
        pad = int(logo_clean_pad) if isinstance(logo_clean_pad, (int, float)) else 6
        clean_bbox = [
            max(0, x1 - pad),
            max(0, y1 - pad),
            min(W, x2 + pad),
            min(H, y2 + pad)
        ]
    if fill_mode == "white":
        ImageDraw.Draw(image).rectangle(clean_bbox, fill=(255, 255, 255))
    elif fill_mode == "gray":
        ImageDraw.Draw(image).rectangle(clean_bbox, fill=(245, 245, 245))
    else:
        _fill_rect_with_sampled_color(image, clean_bbox)

    # 2) 清理字段区域
    module = get_report_type(report_type)
    for field in module.get_fields():
        bx = field["bbox"]
        if fill_mode == "white":
            ImageDraw.Draw(image).rectangle(bx, fill=(255, 255, 255))
        elif fill_mode == "gray":
            ImageDraw.Draw(image).rectangle(bx, fill=(245, 245, 245))
        else:
            _fill_rect_with_sampled_color(image, bx)

    # 3) 针对部分模板的额外静态文字/Logo 区域清理（保守坐标，不影响字段）
    W, H = image.size
    if report_type == "化验_检测报告":
        # 清理右上表头/参考范围可能残留的小字区域（例如“男…”）
        extra_boxes = [
            # 表头右上区域（医生行与首个检验行之间）
            (max(0, int(W*0.75)), max(0, 360), min(W, int(W*0.98)), min(H, 450)),
        ]
    elif report_type == "影像文字报告":
        # 部分模板原始院名/Logo 位于左上角，右上角仅用于新 Logo；
        # 保守清理左上头部区域，不触碰任何字段（字段从 y≈240 开始）。
        extra_boxes = [
            (0, 0, min(W, int(W * 0.48)), min(H, 220)),
        ]
    else:
        extra_boxes = []

    for bx in extra_boxes:
        if fill_mode == "white":
            ImageDraw.Draw(image).rectangle(bx, fill=(255, 255, 255))
        elif fill_mode == "gray":
            ImageDraw.Draw(image).rectangle(bx, fill=(245, 245, 245))
        else:
            _fill_rect_with_sampled_color(image, bx)

    return image
