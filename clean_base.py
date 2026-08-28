"""
回退说明（门诊病历_就诊记录 清理策略）
日期: 2026-08-28
背景: 先前为统一风格，曾在 EMR（门诊病历_就诊记录）上铺设统一浅灰面板并减少逐字段清底，带来版面“带状/面板”观感问题。
本次回退: 取消 EMR 的整块浅灰面板处理，按旧版保守策略：仅字段级清理+顶部页眉带清理（白底），其余保持原模板底色。
范围: 仅影响 EMR；化验/影像/处方仍按现有策略执行。
扩展: 若业务需要，还可进一步关闭 EMR 的顶部页眉带清理，以更贴近“完全旧版”。
"""

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
        # 额外清理（更激进）：
        # - 表头右上区域（医生行与首个检验行之间），常见“参考范围/性别 男/女”残留
        # - 结果表右侧参考范围整列，从表格开始到结尾
        # - 过曝一列更靠左的安全带，防止模板变体导致遗漏（不会影响我们随后渲染的整行文本）
        # 注意：我们先清空，再整行渲染自己的文本，因此即使略微覆盖到行右侧也无副作用。
        extra_boxes = [
            (max(0, int(W*0.60)), 280, min(W, int(W*0.995)), min(H, 540)),   # 表头右上较大清理（更宽更高）
            (max(0, int(W*0.60)), 500, min(W, int(W*0.995)), min(H, 1820)),  # 右侧参考范围列（向左扩展）
            (max(0, int(W*0.78)), 360, min(W, int(W*0.995)), min(H, 1820)),  # 冗余安全带（确保彻底）
        ]
    elif report_type == "影像文字报告":
        # 部分模板原始院名/Logo 位于左上角，右上角仅用于新 Logo；
        # 保守清理左上头部区域，不触碰任何字段（字段从 y≈240 开始）。
        # 同时增加右上角标题带（常见项目栏）清理，以避免模板上“性别/男/女”之类遗留
        extra_boxes = [
            (0, 0, min(W, int(W * 0.48)), min(H, 220)),
            (max(0, int(W*0.68)), 230, min(W, int(W*0.99)), min(H, 300)),
        ]
    elif report_type == "门诊病历_就诊记录":
        # 回退到“解耦前”的保守清理策略：不再铺设整块浅灰面板，避免整体底色变化。
        # 仅按字段 bbox 与顶部页眉带进行清理（由下方通用逻辑与 header 带统一处理）。
        extra_boxes = []
    elif report_type == "医嘱_处方":
        # 处方模板来自手机端病历页面。清理时保留蓝色分区和白色卡片骨架，
        # 仅额外抹掉原截图右下角“下载”悬浮按钮，避免与审核人/处方内容混在一起。
        extra_boxes = [
            (1040, 2050, min(W, 1240), min(H, 2280)),
        ]
    else:
        extra_boxes = []

    for bx in extra_boxes:
        # 对化验单的额外清理区域一律用纯白填充，确保去除“男/女/参考范围”等静态字样
        if report_type == "化验_检测报告":
            ImageDraw.Draw(image).rectangle(bx, fill=(255, 255, 255))
        elif report_type == "门诊病历_就诊记录":
            # 门诊病历不做整块底色覆盖，保持模板原貌（字段区域已在前面逐一清理）。
            ImageDraw.Draw(image).rectangle(bx, fill=(255, 255, 255)) if fill_mode == "white" else _fill_rect_with_sampled_color(image, bx)
        else:
            if fill_mode == "white":
                ImageDraw.Draw(image).rectangle(bx, fill=(255, 255, 255))
            elif fill_mode == "gray":
                ImageDraw.Draw(image).rectangle(bx, fill=(245, 245, 245))
            else:
                _fill_rect_with_sampled_color(image, bx)

    # 4) 统一清理顶端整条“页眉带”（防止模板差异在顶部残留旧Logo/英文名/性别列等）
    #    这里直接用纯白填充，再由后续渲染完整覆盖字段内容，避免任何残影。
    # 顶部页眉带清理：对 EMR（门诊病历_就诊记录）改为邻域采样色，避免在偏灰/泛黄页眉上出现突兀的纯白带；
    # 其他类型保持白底清理，便于统一重绘模板壳。
    header_band_by_type = {
        "影像文字报告": 320,
        "化验_检测报告": 360,
        "医嘱_处方": 260,
        "门诊病历_就诊记录": 260,
    }
    hb = header_band_by_type.get(report_type, 300)
    header_box = (0, 0, W, min(H, hb))
    if report_type == "门诊病历_就诊记录":
        _fill_rect_with_sampled_color(image, header_box)
    else:
        ImageDraw.Draw(image).rectangle(header_box, fill=(255, 255, 255))

    return image
