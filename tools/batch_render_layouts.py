import os
import sys
from pathlib import Path
import argparse
import json
import random
from typing import List

# 保证可直接从 tools/ 目录运行
REPO_ROOT = str(Path(__file__).resolve().parents[1])
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from layout_engine.layouts import list_layouts
from layout_engine.engine import generate_report
from report_types import get_report_type
from case_generalize import HOSPITALS, DEPARTMENTS


def build_content(report_type: str) -> dict:
    module = get_report_type(report_type)
    data = module.generate_data()
    content = dict(data)
    content.setdefault("report_type", report_type)
    content.setdefault("department", random.choice(DEPARTMENTS))
    content["gender"] = "女"
    content.setdefault("title", "检验报告单" if report_type == "化验_检测报告" else report_type)
    return content


def pick_layouts(max_count: int) -> List[str]:
    all_layouts = list(list_layouts().keys())
    # 为了多样性，随机打乱后取前 N 个；如不足 30，就全取
    random.shuffle(all_layouts)
    return all_layouts[:max_count]


def main():
    parser = argparse.ArgumentParser(description="Render up to N different layouts into one folder")
    parser.add_argument("--type", default="化验_检测报告")
    parser.add_argument("--num-per-layout", type=int, default=1, help="每个板式生成数量")
    parser.add_argument("--max-layouts", type=int, default=30, help="最多板式数量")
    parser.add_argument("--output", required=True, help="统一输出目录")
    parser.add_argument("--font-path", default="C:\\Windows\\Fonts\\simsun.ttc")
    args = parser.parse_args()

    if args.type != "化验_检测报告":
        raise SystemExit("当前批量脚本仅支持解耦引擎的化验_检测报告板式")

    os.makedirs(args.output, exist_ok=True)
    out_dir = os.path.join(args.output, args.type)
    os.makedirs(out_dir, exist_ok=True)

    # 选择板式
    # argparse 将参数解析为 args.max_layouts
    layouts = pick_layouts(args.max_layouts)

    # 确保文件名不冲突：查找现有编号
    start_index = 1
    try:
        existing = [
            int(fn[5:10])
            for fn in os.listdir(out_dir)
            if fn.startswith("case_") and fn.endswith(".jpg") and fn[5:10].isdigit()
        ]
        if existing:
            start_index = max(existing) + 1
    except Exception:
        start_index = 1

    i = start_index
    for layout in layouts:
        for _ in range(args.num_per_layout):
            content = build_content(args.type)
            hosp = random.choice(HOSPITALS)
            # 去掉英文与拉丁字符，保留中文部分
            import re
            name = hosp["name"]
            m = re.search(r"[A-Za-z]", name)
            if m:
                name = name[:m.start()]
            content["hospital"] = name.strip() or hosp["name"]

            pid = f"LA{i:05d}"
            content["patient_id"] = pid

            filename = f"case_{i:05d}.jpg"
            out_path = os.path.join(out_dir, filename)
            config = {"font_path": args.font_path, "jpeg_quality": 95}
            generate_report(content, layout, out_path, config)

            with open(out_path.replace('.jpg', '.json'), 'w', encoding='utf-8') as f:
                json.dump({"report_type": args.type, "layout": layout, "content": content}, f, ensure_ascii=False, indent=2)

            i += 1

    # 简要罗列输出的文件
    jpgs = [fn for fn in os.listdir(out_dir) if fn.endswith('.jpg')]
    jsons = [fn for fn in os.listdir(out_dir) if fn.endswith('.json')]
    print(f"Done. Output: {out_dir} (layouts: {len(layouts)}, images: {len(jpgs)}, jsons: {len(jsons)})")


if __name__ == "__main__":
    main()
