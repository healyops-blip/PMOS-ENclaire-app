import os
import argparse
import json
import random
from datetime import datetime
from report_types import get_report_type
from layout_engine.engine import generate_report, list_available_layouts
from case_generalize import HOSPITALS, DEPARTMENTS


def build_content(report_type: str) -> dict:
    module = get_report_type(report_type)
    data = module.generate_data()
    # normalize keys expected by engine
    content = dict(data)
    content.setdefault("report_type", report_type)
    # Department: use existing pool to keep source consistent
    content.setdefault("department", random.choice(DEPARTMENTS))
    # Gender must be female only per requirement
    content["gender"] = "女"
    content.setdefault("title", "检验报告单" if report_type == "化验_检测报告" else report_type)
    return content


def main():
    parser = argparse.ArgumentParser(description="Render reports with decoupled layout engine")
    parser.add_argument("--type", required=True, choices=[
        "化验_检测报告", "影像文字报告", "医嘱_处方", "门诊病历_就诊记录"
    ])
    parser.add_argument("--layout", required=True, choices=list_available_layouts())
    parser.add_argument("--output", default="./result_decoupled")
    parser.add_argument("--num", type=int, default=5)
    parser.add_argument("--start", type=int, default=1, help="起始编号（用于确保跨批次唯一ID）")
    parser.add_argument("--font-path", default="C:\\Windows\\Fonts\\simsun.ttc")
    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)
    out_dir = os.path.join(args.output, args.type)
    os.makedirs(out_dir, exist_ok=True)

    # Ensure unique patient_id within this run using deterministic prefixes per type
    prefix_map = {
        "化验_检测报告": "LA",
        "影像文字报告": "P",
        "医嘱_处方": "PR",
        "门诊病历_就诊记录": "MR",
    }

    used_ids = set()

    # 目前解耦布局仅完善了化验单的样式组合；其他类型将在后续补充独立schema
    if args.type != "化验_检测报告":
        raise SystemExit("当前解耦布局引擎仅支持化验_检测报告（hospital_lab_*）渲染，请使用 case_generalize.py 生成其他类型")

    # 自动从已存在的文件中推断起始编号（除非显式指定 --start）
    start_index = args.start
    if args.start == 1:
        try:
            existing = [
                int(fn[5:10])
                for fn in os.listdir(out_dir)
                if fn.startswith("case_") and fn.endswith(".jpg") and fn[5:10].isdigit()
            ]
            if existing:
                start_index = max(existing) + 1
        except Exception:
            start_index = args.start

    end_idx = start_index + args.num - 1
    def _hospital_cn(name: str) -> str:
        # 去掉英文与拉丁字符，保留中文部分
        import re
        m = re.search(r"[A-Za-z]", name)
        if m:
            name = name[:m.start()]
        return name.strip()

    for i in range(start_index, end_idx + 1):
        content = build_content(args.type)
        # Assign hospital strictly from our constructed source list
        hosp = random.choice(HOSPITALS)
        content["hospital"] = _hospital_cn(hosp["name"]) or hosp["name"]
        # Guarantee unique patient_id in-batch with fixed prefix per type
        prefix = prefix_map.get(args.type, "ID")
        pid = f"{prefix}{i:05d}"
        # Extremely defensive: avoid collisions if any
        while pid in used_ids:
            i2 = i + 1
            pid = f"{prefix}{i2:05d}"
        used_ids.add(pid)
        content["patient_id"] = pid
        # filename
        filename = f"case_{i:05d}.jpg"
        out_path = os.path.join(out_dir, filename)
        config = {
            "font_path": args.font_path,
            "jpeg_quality": 95,
        }
        generate_report(content=content, layout=args.layout, output_path=out_path, config=config)
        # Save a sidecar JSON
        with open(out_path.replace('.jpg', '.json'), 'w', encoding='utf-8') as f:
            json.dump({"report_type": args.type, "layout": args.layout, "content": content}, f, ensure_ascii=False, indent=2)

    print(f"Done. Output: {out_dir}")


if __name__ == "__main__":
    main()
