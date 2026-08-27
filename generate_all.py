#!/usr/bin/env python3
"""
鎵归噺鐢熸垚鎵€鏈夊洓绉嶆姤鍛婄被鍨嬬殑娉涘寲鐥呬緥
纭繚缂栧彿鍏ㄥ眬鍞竴锛岀敓鎴?master truth 鏄犲皠鏂囦欢
"""

import os
import sys
import json
import random
import shutil
import argparse
from datetime import datetime

# 娣诲姞鑴氭湰鎵€鍦ㄧ洰褰曞埌璺緞
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
# 閰嶇疆
# ============================================================

REPORT_TYPES = list_report_types()
NUM_PER_TYPE = 20  # 姣忕绫诲瀷鐢熸垚鏁伴噺

# 瀛椾綋閰嶇疆
FONT_PATH = "C:\\Windows\\Fonts\\msyh.ttc"

def compute_logo_bbox(img_size):
    """鏍规嵁杈撳叆妯℃澘鍥剧墖灏哄锛屽姩鎬佽绠楁洿鑷劧鐨勫彸涓婅 logo 鍖哄煙銆?
    - 璺濈椤堕儴 20px锛屽彸杈硅窛 24px
    - 瀹藉害绾﹀崰瀹藉害鐨?18%锛堝湪 180~280 涔嬮棿瑁佸壀锛?
    - 楂樺害绾﹀崰楂樺害鐨?6%锛堝湪 80~120 涔嬮棿瑁佸壀锛?
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
# 涓荤敓鎴愰€昏緫
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="鎵归噺鐢熸垚鎵€鏈夊洓绉嶆姤鍛婄被鍨嬬殑娉涘寲鐥呬緥"
    )
    parser.add_argument("--output", default="./result", help="杈撳嚭鐩綍锛堟垨鐖剁洰褰曪級")
    parser.add_argument("--num-per-type", type=int, default=20, help="姣忕绫诲瀷鐢熸垚鏁伴噺")
    parser.add_argument("--font-path", default=FONT_PATH, help="瀛椾綋璺緞")
    parser.add_argument("--seed", type=int, default=None, help="闅忔満绉嶅瓙")
    parser.add_argument("--unique-run-dir", action="store_true", help="鍦ㄨ緭鍑虹洰褰曚笅鏂板缓鍞竴瀛愮洰褰曪紝閬垮厤瑕嗙洊鏃х粨鏋?)
    parser.add_argument("--emit-clean-bases", action="store_true", help="瀵煎嚭姣忕绫诲瀷鐨勫共鍑€搴曞浘渚涙鏌?)
    parser.add_argument("--clean-fill-mode", choices=["sample", "white", "gray"], default="sample", help="娓呯悊搴曡壊鐨勬柟寮?)
    parser.add_argument("--logo-clean-mode", choices=["safe", "detect", "none"], default="safe", help="娓呯悊logo鍖哄煙绛栫暐锛歴afe=浠呮墿灞昹ogo妗? detect=妫€娴嬪苟闆? none=鍙湪logo妗嗗唴")
    parser.add_argument("--logo-clean-pad", type=int, default=6, help="safe妯″紡涓?logo 妗嗗悜鍥涘懆鎵╁睍鐨勫儚绱?)
    parser.add_argument("--gender", choices=["鐢?, "濂?, "random"], default="random", help="鎬у埆鐢熸垚绛栫暐锛氱敺/濂?闅忔満")
    parser.add_argument("--pcos-only", action="store_true", default=True, help="浠呰緭鍑轰笌澶氬泭鍗靛发鐩稿叧鐨勫唴瀹癸紙鍗拌薄/寤鸿/璇婃柇绛夊己鍒朵负PCOS鐩稿叧锛夆€斺€旈粯璁ゅ紑鍚?)
    parser.add_argument("--allow-non-pcos", action="store_true", default=False, help="鍏佽鐢熸垚闈濸COS鎻忚堪锛堟樉寮忓紑鍚墠浼氱敓鏁堬級")
    parser.add_argument("--numeric-only", action="store_true", help="浠呬慨鏀规暟鍊煎瓧娈碉紝鍏朵粬鏂囨湰鍥哄畾锛堥粯璁よ仛鐒COS鍦烘櫙锛?)
    parser.add_argument("--jitter-percent", type=float, default=10.0, help="鏁板€肩浉瀵瑰熀鍑嗙殑鏈€澶у亸宸櫨鍒嗘瘮锛堜緥濡?0琛ㄧず卤10%锛?)
    parser.add_argument("--jitter-mode", choices=["off", "first"], default="first", help="鏁板€兼姈鍔ㄥ熀鍑嗭細off鍏抽棴锛沠irst鐢ㄦ湰娆¤繍琛屾瘡绫诲瀷棣栦緥涓哄熀鍑?)
    args = parser.parse_args()

    # 璁剧疆闅忔満绉嶅瓙锛堝彲澶嶇幇锛?
    if args.seed is not None:
        random.seed(args.seed)
        print(f"浣跨敤闅忔満绉嶅瓙: {args.seed}")

    # 楠岃瘉瀛椾綋
    if not os.path.exists(args.font_path):
        print(f"閿欒: 瀛椾綋涓嶅瓨鍦? {args.font_path}")
        sys.exit(1)
    print(f"浣跨敤瀛椾綋: {args.font_path}")

    # 澶勭悊杈撳嚭鐩綍锛氭敮鎸佸敮涓€瀛愮洰褰?
    if args.unique_run_dir:
        run_suffix = datetime.now().strftime("%Y%m%d_%H%M%S")
        if args.seed is not None:
            run_suffix += f"_seed{args.seed}"
        out_root = os.path.join(args.output, run_suffix)
        os.makedirs(out_root, exist_ok=True)
        print(f"浣跨敤鍞竴杈撳嚭瀛愮洰褰? {out_root}")
    else:
        out_root = args.output
        if os.path.exists(out_root):
            print(f"娓呯┖杈撳嚭鐩綍: {out_root}")
            shutil.rmtree(out_root)
        os.makedirs(out_root, exist_ok=True)

    # 澶勭悊 PCOS-only 榛樿绛栫暐锛氶櫎闈炴樉寮?--allow-non-pcos锛屽惁鍒欏己鍒?PCOS
    if args.allow_non_pcos:
        args.pcos_only = False
    else:
        args.pcos_only = True

    # 榛樿閰嶇疆
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

    # 鑾峰彇鑴氭湰鐩綍
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_dir = os.path.join(script_dir, "sample_input")
    logo_dir = os.path.join(script_dir, "logo")

    # Master truth mapping: filename -> truth data
    master_truth = {}

    global_counter = 1  # 鍏ㄥ眬鍞竴缂栧彿璧峰

    total_types = len(REPORT_TYPES)

    # 鏁板€煎熀绾跨紦瀛橈細姣忎釜绫诲瀷浠呭湪棣栨鏍锋湰鏃惰褰?
    baselines = {}

    for idx, report_type in enumerate(REPORT_TYPES):
        print(f"\n{'='*60}")
        print(f"鐢熸垚绫诲瀷 [{idx+1}/{total_types}]: {report_type}")
        print(f"{'='*60}")

        # 鍒涘缓鎶ュ憡绫诲瀷瀛愮洰褰?
        report_dir = os.path.join(out_root, report_type)
        os.makedirs(report_dir, exist_ok=True)

        # 鑾峰彇杈撳叆鍥剧墖
        input_path = os.path.join(input_dir, f"{report_type}.jpg")
        if not os.path.exists(input_path):
            print(f"閿欒: 杈撳叆鍥剧墖涓嶅瓨鍦? {input_path}")
            sys.exit(1)

        # 鑾峰彇鎶ュ憡绫诲瀷妯″潡
        module = get_report_type(report_type)

        # Logo bbox - 鍔ㄦ€佸熀浜庢ā鏉垮昂瀵歌绠楋紙鍙充笂瑙掞級锛岄伩鍏嶁€滀綅缃緢濂囨€€?
        with Image.open(input_path) as _im:
            logo_bbox = compute_logo_bbox(_im.size)
        print(f"  浣跨敤 logo 鍖哄煙: {logo_bbox}")

        # 鏋勫缓骞朵繚瀛樷€滃共鍑€搴曞浘鈥濓紙娓呴櫎鏃ч櫌鍚嶅拰鎵€鏈夋枃瀛楁锛?
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
            # 楂樿川閲忎繚瀛樹互閬垮厤澶辩湡
            clean_base.save(clean_base_path, format="JPEG", quality=98)
            print(f"  骞插噣搴曞浘: {clean_base_path}")
            input_for_cases = clean_base_path
        except Exception as e:
            print(f"[WARNING] 鏋勫缓骞插噣搴曞浘澶辫触锛屽洖閫€浣跨敤鍘熸ā鏉? {e}")
            input_for_cases = input_path

        # 鐢熸垚鏈被鍨嬬梾渚?
        # 鏂囦欢鍚嶅湪姣忎釜鎶ュ憡绫诲瀷鐩綍鍐呯嫭绔嬬紪鍙凤紝閬垮厤涓嬫父鎸?
        # result/<鎶ュ憡绫诲瀷>/case_00001.jpg ... case_000NN.jpg 璇诲彇鏃惰鍒ょ己澶便€?
        # doc_id 浠嶇劧浣跨敤 global_counter锛屼繚璇佽法绫诲瀷鍞竴銆?
        for i in range(args.num_per_type):
            local_counter = i + 1
            filename = f"case_{local_counter:05d}.jpg"
            output_path = os.path.join(report_dir, filename)

            # 闅忔満閫夋嫨鍖婚櫌
            hospital_info = random.choice(HOSPITALS)

            print(f"  [{global_counter:03d}] {report_type}/{filename} - {hospital_info['name']}")

            # 鐢熸垚鏁版嵁
            data = module.generate_data()
            data["department"] = random.choice(DEPARTMENTS)
            data["hospital"] = hospital_info["name"]

            # 鍏ㄥ眬鎬у埆瑕嗙洊锛堝鎸囧畾锛?
            if args.gender != "random":
                data["gender"] = args.gender

            # 鏃ュ織锛氱‘璁ゆ€у埆
            try:
                print(f"    鎬у埆: {data.get('gender', '鏈煡')}")
            except Exception:
                pass

            # 缁熶竴骞剁‘淇濈梾鍘嗗彿锛坧atient_id锛夊叏灞€鍞竴锛氫娇鐢ㄧ被鍨嬪墠缂€ + 鍏ㄥ眬璁℃暟
            prefix_map = {
                "褰卞儚鏂囧瓧鎶ュ憡": "P",
                "鍖栭獙_妫€娴嬫姤鍛?: "LA",
                "鍖诲槺_澶勬柟": "PR",
                "闂ㄨ瘖鐥呭巻_灏辫瘖璁板綍": "MR",
            }
            pid_prefix = prefix_map.get(report_type, "ID")
            data["patient_id"] = f"{pid_prefix}{global_counter:05d}"

                # 浠匬COS鐩稿叧锛氳鐩栧嵃璞?寤鸿/璇婃柇/鐥囩姸绛夋枃鏈负澶氬泭鍗靛发鐩稿叧鍐呭
            if args.pcos_only:
                # 缁熶竴绉戝鍒颁笌PCOS鐩稿叧
                data["department"] = "鐢熸畺绉?
                if report_type == "褰卞儚鏂囧瓧鎶ュ憡":
                    # 褰卞儚鏂囧瓧鎶ュ憡蹇呴』鏁村彞瑕嗙洊娴嬮噺鐩稿叧琛岋細鏁板瓧浠嶇敱 data 鐢熸垚锛?
                    # 浣嗕笉鍏佽鏁板瓧绾ц创鐗囷紝閬垮厤鏃у彞娈嬬暀鍜岄敊浣嶃€?
                    data["pelvic_effusion"] = "鏃?
                    data["pelvic_effusion_line"] = "瀛愬鐩磋偁闄风獫绉恫锛氭棤"
                elif report_type == "闂ㄨ瘖鐥呭巻_灏辫瘖璁板綍":
                    # 甯歌PCOS鐩稿叧鐥囩姸
                    data["symptom1"] = "鏈堢粡涓嶈皟"
                    data["symptom2"] = "鐥ょ柈"
                    data["symptom3"] = "澶氭瘺"
                    data["symptom4"] = "浣撻噸澧炲姞"
                    data["symptom5"] = "鍗靛发澶氬泭鏍锋敼鍙?
                    data["diagnosis"] = "澶氬泭鍗靛发缁煎悎寰?
                    data["treatment"] = "鐢熸椿鏂瑰紡骞查锛屽繀瑕佹椂鑽墿娌荤枟"
                    data["advice"] = "寤鸿鍐呭垎娉岃瘎浼颁笌闅忚锛屾帶鍒朵綋閲嶏紝瑙勫緥浣滄伅"
                elif report_type == "鍖诲槺_澶勬柟":
                    data["diagnosis"] = "澶氬泭鍗靛发缁煎悎寰?
                elif report_type == "鍖栭獙_妫€娴嬫姤鍛?:
                    # 鍖栭獙鍗曟棤璇婃柇/鍗拌薄/寤鸿瀛楁锛屼繚鎸佹暟鍊煎彉鍔?
                    pass

            # 浠呬慨鏀规暟鍊硷細鍐荤粨闈炴暟鍊兼枃鏈负鍥哄畾PCOS鐩稿叧甯搁噺
            if args.numeric_only:
                # 閫氱敤鍥哄畾椤?
                data["name"] = "寮犱笁"
                data["doctor"] = "寮犲尰鐢?
                data["department"] = "鐢熸畺绉?
                data["exam_date"] = "2026-08-01"

                # 鍚勭被鍨婸COS鐩稿叧鍥哄畾鏂囨湰
                if report_type == "褰卞儚鏂囧瓧鎶ュ憡":
                    # numeric-only 瀵瑰奖鍍忔姤鍛婅〃绀衡€滃彧鏀瑰彉鍙ュ唴鏁板€尖€濓紝浣嗘覆鏌撲粛鎸夋暣鍙ヨ鐩栥€?
                    data["pelvic_effusion"] = "鏃?
                    data["pelvic_effusion_line"] = "瀛愬鐩磋偁闄风獫绉恫锛氭棤"
                elif report_type == "鍖栭獙_妫€娴嬫姤鍛?:
                    # 鏍囬/妯℃澘瀛楁鏈韩鍥哄畾锛屼繚鎸佹暟鍊奸殢鏈?
                    pass
                elif report_type == "闂ㄨ瘖鐥呭巻_灏辫瘖璁板綍":
                    data["symptom1"] = "鏈堢粡涓嶈皟"
                    data["symptom2"] = "鐥ょ柈"
                    data["symptom3"] = "澶氭瘺"
                    data["symptom4"] = "浣撻噸澧炲姞"
                    data["symptom5"] = "鍗靛发澶氬泭鏍锋敼鍙?
                    data["diagnosis"] = "澶氬泭鍗靛发缁煎悎寰?
                    data["treatment"] = "鐢熸椿鏂瑰紡骞查锛屽繀瑕佹椂鑽墿娌荤枟"
                    data["advice"] = "寤鸿鍐呭垎娉岃瘎浼颁笌闅忚锛屾帶鍒朵綋閲嶏紝瑙勫緥浣滄伅"
                elif report_type == "鍖诲槺_澶勬柟":
                    data["diagnosis"] = "澶氬泭鍗靛发缁煎悎寰?
                    # 鍥哄畾澶勬柟涓?涓狿COS甯哥敤鑽?琛ュ厖鍓傦紝濉弧妯℃澘3涓嵂浣嶏紝閬垮厤 clean base 鍚庡嚭鐜扮┖鐧借嵂妲姐€?
                    data["med1_name"] = "鐩愰吀浜岀敳鍙岃儘"
                    data["med1_spec"] = "0.5g"
                    data["med1_freq"] = "姣忔棩3娆?
                    data["med1_days"] = "闀挎湡"
                    data["med1_usage"] = "鍙ｆ湇"
                    data["med1_display"] = "鐩愰吀浜岀敳鍙岃儘鐗囷紙鏍煎崕姝級 0.5g*20鐗?
                    data["med1_form"] = "鐗囧墏"
                    data["med1_dose"] = "姣忔1鐗?
                    data["med1_total"] = "20鐗?
                    data["med2_name"] = "鐐旈泴閱囩幆涓欏瓡閰墖"
                    data["med2_spec"] = "鐐旈泴閱?.035mg+閱嬮吀鐜笝瀛曢叜2mg"
                    data["med2_freq"] = "姣忔棩1娆?
                    data["med2_days"] = "鎸夊懆鏈?
                    data["med2_usage"] = "鍙ｆ湇"
                    data["med2_display"] = "鐐旈泴閱囩幆涓欏瓡閰墖锛堣揪鑻?35锛?21鐗?
                    data["med2_form"] = "鐗囧墏"
                    data["med2_dose"] = "姣忔1鐗?
                    data["med2_total"] = "21鐗?
                    data["med3_name"] = "鑲岄唶"
                    data["med3_spec"] = "2g"
                    data["med3_freq"] = "姣忔棩2娆?
                    data["med3_days"] = "闀挎湡"
                    data["med3_usage"] = "鍙ｆ湇"
                    data["med3_display"] = "鑲岄唶绮夊墏 2g*30琚?
                    data["med3_form"] = "绮夊墏"
                    data["med3_dose"] = "姣忔1琚?
                    data["med3_total"] = "30琚?
                    data["usage"] = "鍙ｆ湇"
                    data["treatment_plan"] = "鎺у埗浣撻噸锛岃皟鏁存湀缁忓懆鏈燂紝瑙勫緥澶嶈瘖璇勪及"

            # 鍦ㄨ繖閲屾寜闇€闄愬埗鏁板€间粎鍦眏itter鑼冨洿鍐呭彉鍔?
            if args.jitter_mode != "off":
                def get_specs(rt):
                    # 杩斿洖鍚勭被鍨嬫暟鍊煎瓧娈佃鏍硷紙绫诲瀷銆佽寖鍥淬€佷繚鐣欏皬鏁颁綅锛?
                    if rt == "褰卞儚鏂囧瓧鎶ュ憡":
                        return {
                            # 鍗靛发灏哄锛氭绫筹紝鏁存暟
                            "right_ovary_length": {"type": "int", "min": 25, "max": 40},
                            "right_ovary_width": {"type": "int", "min": 15, "max": 25},
                            "right_ovary_height": {"type": "int", "min": 20, "max": 35},
                            "left_ovary_length": {"type": "int", "min": 25, "max": 40},
                            "left_ovary_width": {"type": "int", "min": 15, "max": 25},
                            "left_ovary_height": {"type": "int", "min": 20, "max": 35},
                            # 鍩虹鍗垫场锛氫釜锛屾暣鏁?
                            "follicle_count_right": {"type": "int", "min": 5, "max": 30},
                            "follicle_count_left": {"type": "int", "min": 5, "max": 30},
                        }
                    elif rt == "鍖栭獙_妫€娴嬫姤鍛?:
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
                            # 灏忔暟涓€浣?
                            "tg": {"type": "float", "min": 0.5, "max": 2.5, "decimals": 1},
                            "hdl": {"type": "float", "min": 0.8, "max": 2.0, "decimals": 1},
                            "ldl": {"type": "float", "min": 2.0, "max": 4.0, "decimals": 1},
                            "ca": {"type": "float", "min": 2.0, "max": 3.0, "decimals": 1},
                            "k": {"type": "float", "min": 3.5, "max": 5.5, "decimals": 1},
                            "na": {"type": "int", "min": 130, "max": 150},
                            "cl": {"type": "int", "min": 95, "max": 110},
                            # 灏忔暟浣嶅悇涓嶇浉鍚?
                            "tsh": {"type": "float", "min": 0.2, "max": 5.0, "decimals": 2},
                            "ft3": {"type": "float", "min": 2.0, "max": 5.0, "decimals": 1},
                            "ft4": {"type": "float", "min": 10.0, "max": 25.0, "decimals": 1},
                        }
                    elif rt == "闂ㄨ瘖鐥呭巻_灏辫瘖璁板綍":
                        return {
                            # 灏嗕綋娓╂姈鍔ㄨ寖鍥撮檺鍒跺湪 37.3~37.8锛屼笖淇濈暀1浣嶅皬鏁?
                            "temp": {"type": "float", "min": 37.3, "max": 37.8, "decimals": 1},
                            "hr": {"type": "int", "min": 50, "max": 120},
                            "rr": {"type": "int", "min": 12, "max": 25},
                            # 琛€鍘嬬壒娈婏細瀛楃涓测€滄敹缂?鑸掑紶鈥?
                            "bp": {"type": "bp", "min": (90, 50), "max": (150, 100)},
                            "total_cost": {"type": "int", "min": 50, "max": 5000},
                            "followup_days": {"type": "int", "min": 1, "max": 30},
                        }
                    elif rt == "鍖诲槺_澶勬柟":
                        return {
                            "dose_count": {"type": "int", "min": 1, "max": 4},
                            "total_amount": {"type": "int", "min": 1, "max": 100},
                        }
                    return {}

                def apply_jitter(rt, datum, baseline_map, pct):
                    specs = get_specs(rt)
                    # 寤虹珛/鑾峰彇鍩虹嚎
                    if rt not in baseline_map:
                        base = {}
                        for k, spec in specs.items():
                            if k in datum:
                                if spec["type"] == "bp":
                                    # 瑙ｆ瀽鈥渟/d鈥?
                                    try:
                                        s, d = str(datum.get(k, "")).split("/")
                                        base[k] = (int(s), int(d))
                                    except Exception:
                                        base[k] = None
                                else:
                                    base[k] = datum.get(k)
                        baseline_map[rt] = base
                        return datum  # 棣栦緥浣滀负鍩虹嚎锛屼笉寮哄埗鏀舵暃

                    base = baseline_map[rt]
                    for k, spec in specs.items():
                        if k not in datum or base.get(k) is None:
                            continue
                        b = base[k]
                        p = max(0.0, pct) / 100.0
                        if spec["type"] == "bp":
                            # s/d 鍒嗗埆鎶栧姩
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
                                # float锛屾牴鎹甦ecimals淇濈暀
                                dec = spec.get("decimals", 1)
                                v_new = round(v_new, dec)
                            datum[k] = v_new
                    return datum

                data = apply_jitter(report_type, data, baselines, args.jitter_percent)

            # jitter / 鍥哄畾鍊艰鐩栧悗锛屽奖鍍忔姤鍛婅鐢ㄦ渶鏂版暟瀛楅噸寤哄畬鏁村彞锛?
            # 淇濊瘉鍥剧墖鍙ュ瓙鍜?JSON 鏁板€煎畬鍏ㄤ竴鑷淬€?
            if report_type == "褰卞儚鏂囧瓧鎶ュ憡" and hasattr(module, "refresh_text_lines"):
                module.refresh_text_lines(data)

            # 鏋勫缓 truth锛氬繀椤诲湪 jitter 涔嬪悗锛岀‘淇?JSON 鏁板€间笌鍥剧墖涓€鑷淬€?
            truth = build_truth_data(report_type, hospital_info, data, filename)

            # 鐢熸垚鐥呬緥鍥剧墖锛堜紶鍏?data 閬垮厤浜屾鐢熸垚锛?
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

            # 璁板綍鍒?master truth锛堝唴鑱?truth 浠ヤ究鐩存帴浣跨敤锛屽悓鏃朵繚鐣欐枃浠惰矾寰勶級
            # 鍥犱负涓嶅悓鎶ュ憡绫诲瀷鐩綍鍐呬細澶嶇敤 case_00001.jpg 绛夋枃浠跺悕锛?
            # 椤跺眰 key 浣跨敤鐩稿璺緞锛岄伩鍏嶅悓鍚嶆潯鐩簰鐩歌鐩栥€?
            truth_rel = os.path.join(report_type, filename.replace(".jpg", ".json"))
            image_rel = os.path.join(report_type, filename)
            master_truth[image_rel] = {
                "report_type": report_type,
                "hospital": hospital_info["name"],
                "department": data.get("department", ""),
                "truth_file": truth_rel,
                "truth": truth
            }

            global_counter += 1

    # 淇濆瓨 master truth 鏄犲皠
    master_truth_path = os.path.join(out_root, "truth_mapping.json")
    with open(master_truth_path, "w", encoding="utf-8") as f:
        json.dump(master_truth, f, ensure_ascii=False, indent=2)

    print(f"\n{'='*60}")
    print(f"鍏ㄩ儴瀹屾垚锛?)
    print(f"鎬荤敓鎴愭暟閲? {global_counter - 1} 涓梾渚?)
    print(f"鎶ュ憡绫诲瀷: {', '.join(REPORT_TYPES)}")
    print(f"杈撳嚭鐩綍: {os.path.abspath(out_root)}")
    print(f"Master truth 鏄犲皠: {master_truth_path}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
