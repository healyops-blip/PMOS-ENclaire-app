#!/usr/bin/env python3
"""
批量生成所有四种报告类型的泛化病例
确保编号全局唯一，生成 master truth 映射文件
"""

import os
import sys
import json
import random
import shutil
import argparse
from datetime import datetime

# 添加脚本所在目录到路径
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

from case_generalize import (
    HOSPITALS, DEPARTMENTS,
    load_font, fit_font, inpaint_region, replace_text, replace_logo,
    augment_image, save_with_compression, render_value,
    generate_case, build_truth_data,
)
from clean_base import build_clean_base_image
from report_types import get_report_type, list_report_types
from PIL import Image

# ============================================================
# 配置
# ============================================================

REPORT_TYPES = list_report_types()
NUM_PER_TYPE = 20  # 每种类型生成数量

# 字体配置
FONT_PATH = "C:\\Windows\\Fonts\\simkai.ttf"

def compute_logo_bbox(img_size):
    """根据输入模板图片尺寸，动态计算更自然的右上角 logo 区域。
    - 距离顶部 20px，右边距 24px
    - 宽度约占宽度的 18%（在 180~280 之间裁剪）
    - 高度约占高度的 6%（在 80~120 之间裁剪）
    """
    w, h = img_size
    margin_r = 24
    top = 20
    box_w = max(180, min(280, int(w * 0.18)))
    box_h = max(80, min(120, int(h * 0.06)))
    x2 = max(margin_r, w - margin_r)
    x1 = max(0, x2 - box_w)
    y1 = top
    y2 = min(h, y1 + box_h)
    return [x1, y1, x2, y2]

# ============================================================
# 主生成逻辑
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="批量生成所有四种报告类型的泛化病例"
    )
    parser.add_argument("--output", default="./result", help="输出目录（或父目录）")
    parser.add_argument("--num-per-type", type=int, default=20, help="每种类型生成数量")
    parser.add_argument("--font-path", default=FONT_PATH, help="字体路径")
    parser.add_argument("--seed", type=int, default=None, help="随机种子")
    parser.add_argument("--unique-run-dir", action="store_true", help="在输出目录下新建唯一子目录，避免覆盖旧结果")
    parser.add_argument("--emit-clean-bases", action="store_true", help="导出每种类型的干净底图供检查")
    parser.add_argument("--clean-fill-mode", choices=["sample", "white", "gray"], default="sample", help="清理底色的方式")
    parser.add_argument("--logo-clean-mode", choices=["safe", "detect", "none"], default="none", help="清理logo区域策略：safe=仅扩展logo框; detect=检测并集; none=只在logo框内")
    parser.add_argument("--logo-clean-pad", type=int, default=6, help="safe模式下 logo 框向四周扩展的像素")
    parser.add_argument("--gender", choices=["男", "女", "random"], default="random", help="性别生成策略：男/女/随机")
    parser.add_argument("--pcos-only", action="store_true", help="仅输出与多囊卵巢相关的内容（印象/建议/诊断等强制为PCOS相关）")
    parser.add_argument("--numeric-only", action="store_true", help="仅修改数值字段，其他文本固定（默认聚焦PCOS场景）")
    parser.add_argument("--jitter-percent", type=float, default=10.0, help="数值相对基准的最大偏差百分比（例如10表示±10%）")
    parser.add_argument("--jitter-mode", choices=["off", "first"], default="first", help="数值抖动基准：off关闭；first用本次运行每类型首例为基准")
    args = parser.parse_args()

    # 设置随机种子（可复现）
    if args.seed is not None:
        random.seed(args.seed)
        print(f"使用随机种子: {args.seed}")

    # 验证字体
    if not os.path.exists(args.font_path):
        print(f"错误: 字体不存在: {args.font_path}")
        sys.exit(1)
    print(f"使用字体: {args.font_path}")

    # 处理输出目录：支持唯一子目录
    if args.unique_run_dir:
        run_suffix = datetime.now().strftime("%Y%m%d_%H%M%S")
        if args.seed is not None:
            run_suffix += f"_seed{args.seed}"
        out_root = os.path.join(args.output, run_suffix)
        os.makedirs(out_root, exist_ok=True)
        print(f"使用唯一输出子目录: {out_root}")
    else:
        out_root = args.output
        if os.path.exists(out_root):
            print(f"清空输出目录: {out_root}")
            shutil.rmtree(out_root)
        os.makedirs(out_root, exist_ok=True)

    # 默认配置
    config = {
        "font_path": args.font_path,
        "rotation_range": [-1.0, 1.0],
        "brightness_range": [0.95, 1.05],
        "contrast_range": [0.95, 1.05],
        "blur_probability": 0.2,
        "noise_probability": 0.2,
        "noise_std": 3,
        "jpeg_quality_min": 85,
        "jpeg_quality_max": 100
    }

    # 获取脚本目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_dir = os.path.join(script_dir, "sample_input")
    logo_dir = os.path.join(script_dir, "logo")

    # Master truth mapping: filename -> truth data
    master_truth = {}

    global_counter = 1  # 全局唯一编号起始

    total_types = len(REPORT_TYPES)

    # 数值基线缓存：每个类型仅在首次样本时记录
    baselines = {}

    for idx, report_type in enumerate(REPORT_TYPES):
        print(f"\n{'='*60}")
        print(f"生成类型 [{idx+1}/{total_types}]: {report_type}")
        print(f"{'='*60}")

        # 创建报告类型子目录
        report_dir = os.path.join(out_root, report_type)
        os.makedirs(report_dir, exist_ok=True)

        # 获取输入图片
        input_path = os.path.join(input_dir, f"{report_type}.jpg")
        if not os.path.exists(input_path):
            print(f"错误: 输入图片不存在: {input_path}")
            sys.exit(1)

        # 获取报告类型模块
        module = get_report_type(report_type)

        # Logo bbox - 动态基于模板尺寸计算（右上角），避免“位置很奇怪”
        with Image.open(input_path) as _im:
            logo_bbox = compute_logo_bbox(_im.size)
        print(f"  使用 logo 区域: {logo_bbox}")

        # 构建并保存“干净底图”（清除旧院名和所有文字框）
        try:
            clean_base = build_clean_base_image(
                input_path, report_type, logo_bbox,
                fill_mode=args.clean_fill_mode,
                logo_clean_mode=args.logo_clean_mode,
                logo_clean_pad=args.logo_clean_pad
            )
            clean_dir = os.path.join(out_root, "_clean_bases")
            os.makedirs(clean_dir, exist_ok=True)
            clean_base_path = os.path.join(clean_dir, f"{report_type}.jpg")
            # 高质量保存以避免失真
            clean_base.save(clean_base_path, format="JPEG", quality=98)
            print(f"  干净底图: {clean_base_path}")
            input_for_cases = clean_base_path
        except Exception as e:
            print(f"[WARNING] 构建干净底图失败，回退使用原模板: {e}")
            input_for_cases = input_path

        # 生成本类型病例
        for i in range(args.num_per_type):
            filename = f"case_{global_counter:05d}.jpg"
            output_path = os.path.join(report_dir, filename)

            # 随机选择医院
            hospital_info = random.choice(HOSPITALS)

            print(f"  [{global_counter:03d}] {report_type}/{filename} - {hospital_info['name']}")

            # 生成数据
            data = module.generate_data()
            data["department"] = random.choice(DEPARTMENTS)

            # 全局性别覆盖（如指定）
            if args.gender != "random":
                data["gender"] = args.gender

            # 日志：确认性别
            try:
                print(f"    性别: {data.get('gender', '未知')}")
            except Exception:
                pass

            # 仅PCOS相关：覆盖印象/建议/诊断/症状等文本为多囊卵巢相关内容
            if args.pcos_only:
                # 统一科室到与PCOS相关
                data["department"] = "生殖科"
                if report_type == "影像文字报告":
                    data["impression"] = "双侧卵巢多囊样改变"
                    data["recommendation"] = "建议结合临床及内分泌评估，生活方式干预，必要时复查"
                elif report_type == "门诊病历_就诊记录":
                    # 常见PCOS相关症状
                    data["symptom1"] = "月经不调"
                    data["symptom2"] = "痤疮"
                    data["symptom3"] = "多毛"
                    data["symptom4"] = "体重增加"
                    data["symptom5"] = "卵巢多囊样改变"
                    data["diagnosis"] = "多囊卵巢综合征"
                    data["treatment"] = "生活方式干预，必要时药物治疗"
                    data["advice"] = "建议内分泌评估与随访，控制体重，规律作息"
                elif report_type == "医嘱_处方":
                    data["diagnosis"] = "多囊卵巢综合征"
                elif report_type == "化验_检测报告":
                    # 化验单无诊断/印象/建议字段，保持数值变动
                    pass

            # 仅修改数值：冻结非数值文本为固定PCOS相关常量
            if args.numeric_only:
                # 通用固定项
                data["name"] = "张三"
                data["doctor"] = "张医生"
                data["department"] = "生殖科"
                data["exam_date"] = "2026-08-01"
                # 各类型固定病历号格式
                if report_type == "影像文字报告":
                    data["patient_id"] = "P000000"
                elif report_type == "化验_检测报告":
                    data["patient_id"] = "LA00000"
                elif report_type == "医嘱_处方":
                    data["patient_id"] = "PR00000"
                elif report_type == "门诊病历_就诊记录":
                    data["patient_id"] = "MR00000"

                # 各类型PCOS相关固定文本
                if report_type == "影像文字报告":
                    data["impression"] = "双侧卵巢多囊样改变"
                    data["recommendation"] = "建议结合临床及内分泌评估，生活方式干预，必要时复查"
                    data["pelvic_effusion"] = "无"  # 类别固定
                elif report_type == "化验_检测报告":
                    # 标题/模板字段本身固定，保持数值随机
                    pass
                elif report_type == "门诊病历_就诊记录":
                    data["symptom1"] = "月经不调"
                    data["symptom2"] = "痤疮"
                    data["symptom3"] = "多毛"
                    data["symptom4"] = "体重增加"
                    data["symptom5"] = "卵巢多囊样改变"
                    data["diagnosis"] = "多囊卵巢综合征"
                    data["treatment"] = "生活方式干预，必要时药物治疗"
                    data["advice"] = "建议内分泌评估与随访，控制体重，规律作息"
                elif report_type == "医嘱_处方":
                    data["diagnosis"] = "多囊卵巢综合征"
                    # 固定处方为PCOS常用：二甲双胍
                    data["med1_name"] = "二甲双胍"
                    data["med1_spec"] = "0.5g"
                    data["med1_freq"] = "每日3次"
                    data["med1_days"] = "长期"
                    data["med2_name"] = ""
                    data["med2_spec"] = ""
                    data["med2_freq"] = ""
                    data["med2_days"] = ""
                    data["med3_name"] = ""
                    data["med3_spec"] = ""
                    data["med3_freq"] = ""
                    data["med3_days"] = ""
                    data["usage"] = "口服"

            # 构建 truth
            truth = build_truth_data(report_type, hospital_info, data, filename)

            # 在这里按需限制数值仅在±jitter范围内变动
            if args.jitter_mode != "off":
                def get_specs(rt):
                    # 返回各类型数值字段规格（类型、范围、保留小数位）
                    if rt == "影像文字报告":
                        return {
                            # 卵巢尺寸：毫米，整数
                            "right_ovary_length": {"type": "int", "min": 25, "max": 40},
                            "right_ovary_width": {"type": "int", "min": 15, "max": 25},
                            "right_ovary_height": {"type": "int", "min": 20, "max": 35},
                            "left_ovary_length": {"type": "int", "min": 25, "max": 40},
                            "left_ovary_width": {"type": "int", "min": 15, "max": 25},
                            "left_ovary_height": {"type": "int", "min": 20, "max": 35},
                            # 基础卵泡：个，整数
                            "follicle_count_right": {"type": "int", "min": 5, "max": 30},
                            "follicle_count_left": {"type": "int", "min": 5, "max": 30},
                        }
                    elif rt == "化验_检测报告":
                        return {
                            "wbc": {"type": "int", "min": 4, "max": 12},
                            "rbc": {"type": "int", "min": 4, "max": 6},
                            "hgb": {"type": "int", "min": 110, "max": 180},
                            "plt": {"type": "int", "min": 100, "max": 350},
                            "alt": {"type": "int", "min": 5, "max": 45},
                            "ast": {"type": "int", "min": 5, "max": 45},
                            "tbil": {"type": "int", "min": 3, "max": 25},
                            "dbil": {"type": "int", "min": 0, "max": 10},
                            "bun": {"type": "int", "min": 2, "max": 8},
                            "crea": {"type": "int", "min": 40, "max": 120},
                            "glu": {"type": "int", "min": 3, "max": 8},
                            "cho": {"type": "int", "min": 3, "max": 6},
                            # 小数一位
                            "tg": {"type": "float", "min": 0.5, "max": 2.5, "decimals": 1},
                            "hdl": {"type": "float", "min": 0.8, "max": 2.0, "decimals": 1},
                            "ldl": {"type": "float", "min": 2.0, "max": 4.0, "decimals": 1},
                            "ca": {"type": "float", "min": 2.0, "max": 3.0, "decimals": 1},
                            "k": {"type": "float", "min": 3.5, "max": 5.5, "decimals": 1},
                            "na": {"type": "int", "min": 130, "max": 150},
                            "cl": {"type": "int", "min": 95, "max": 110},
                            # 小数位各不相同
                            "tsh": {"type": "float", "min": 0.2, "max": 5.0, "decimals": 2},
                            "ft3": {"type": "float", "min": 2.0, "max": 5.0, "decimals": 1},
                            "ft4": {"type": "float", "min": 10.0, "max": 25.0, "decimals": 1},
                        }
                    elif rt == "门诊病历_就诊记录":
                        return {
                            # 将体温抖动范围限制在 37.3~37.8，且保留1位小数
                            "temp": {"type": "float", "min": 37.3, "max": 37.8, "decimals": 1},
                            "hr": {"type": "int", "min": 50, "max": 120},
                            "rr": {"type": "int", "min": 12, "max": 25},
                            # 血压特殊：字符串“收缩/舒张”
                            "bp": {"type": "bp", "min": (90, 50), "max": (150, 100)},
                            "total_cost": {"type": "int", "min": 50, "max": 5000},
                            "followup_days": {"type": "int", "min": 1, "max": 30},
                        }
                    elif rt == "医嘱_处方":
                        return {
                            "dose_count": {"type": "int", "min": 1, "max": 4},
                            "total_amount": {"type": "int", "min": 1, "max": 100},
                        }
                    return {}

                def apply_jitter(rt, datum, baseline_map, pct):
                    specs = get_specs(rt)
                    # 建立/获取基线
                    if rt not in baseline_map:
                        base = {}
                        for k, spec in specs.items():
                            if k in datum:
                                if spec["type"] == "bp":
                                    # 解析“s/d”
                                    try:
                                        s, d = str(datum.get(k, "")).split("/")
                                        base[k] = (int(s), int(d))
                                    except Exception:
                                        base[k] = None
                                else:
                                    base[k] = datum.get(k)
                        baseline_map[rt] = base
                        return datum  # 首例作为基线，不强制收敛

                    base = baseline_map[rt]
                    for k, spec in specs.items():
                        if k not in datum or base.get(k) is None:
                            continue
                        b = base[k]
                        p = max(0.0, pct) / 100.0
                        if spec["type"] == "bp":
                            # s/d 分别抖动
                            try:
                                s_val, d_val = str(datum.get(k)).split("/")
                                s_val = int(s_val); d_val = int(d_val)
                            except Exception:
                                continue
                            s_base, d_base = b
                            s_lo = max(spec["min"][0], int(round(s_base * (1 - p))))
                            s_hi = min(spec["max"][0], int(round(s_base * (1 + p))))
                            d_lo = max(spec["min"][1], int(round(d_base * (1 - p))))
                            d_hi = min(spec["max"][1], int(round(d_base * (1 + p))))
                            s_new = min(max(s_val, s_lo), s_hi)
                            d_new = min(max(d_val, d_lo), d_hi)
                            datum[k] = f"{s_new}/{d_new}"
                        else:
                            v = datum.get(k)
                            v_num = float(v)
                            lo = spec.get("min", -1e9)
                            hi = spec.get("max", 1e9)
                            lo_p = max(lo, b * (1 - p))
                            hi_p = min(hi, b * (1 + p))
                            v_new = min(max(v_num, lo_p), hi_p)
                            if spec["type"] == "int":
                                v_new = int(round(v_new))
                            else:
                                # float，根据decimals保留
                                dec = spec.get("decimals", 1)
                                v_new = round(v_new, dec)
                            datum[k] = v_new
                    return datum

                data = apply_jitter(report_type, data, baselines, args.jitter_percent)

            # 生成病例图片（传入 data 避免二次生成）
            generate_case(
                input_path=input_for_cases,
                output_path=output_path,
                config=config,
                case_index=global_counter,
                report_type=report_type,
                hospital_info=hospital_info,
                logo_bbox=logo_bbox,
                truth_data=truth,
                data=data
            )

            # 记录到 master truth（内联 truth 以便直接使用，同时保留文件路径）
            master_truth[filename] = {
                "report_type": report_type,
                "hospital": hospital_info["name"],
                "department": data.get("department", ""),
                "truth_file": os.path.join(report_type, filename.replace(".jpg", ".json")),
                "truth": truth
            }

            global_counter += 1

    # 保存 master truth 映射
    master_truth_path = os.path.join(out_root, "truth_mapping.json")
    with open(master_truth_path, "w", encoding="utf-8") as f:
        json.dump(master_truth, f, ensure_ascii=False, indent=2)

    print(f"\n{'='*60}")
    print(f"全部完成！")
    print(f"总生成数量: {global_counter - 1} 个病例")
    print(f"报告类型: {', '.join(REPORT_TYPES)}")
    print(f"输出目录: {os.path.abspath(out_root)}")
    print(f"Master truth 映射: {master_truth_path}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()