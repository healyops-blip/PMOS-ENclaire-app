#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
读取 d:\hackathon_26\result\ocr_eval_latest.json（或指定路径），
按“类型”统计并打印一张表：完成 OK Error 有差异 字段准确率 字段匹配。

用法：
  python d:\hackathon_26\tools\print_eval_report.py --input d:\hackathon_26\result\ocr_eval_latest.json
不传 --input 时默认读取 d:\hackathon_26\result\ocr_eval_latest.json
会将同样的表保存为 d:\hackathon_26\result\field_accuracy_report.txt
"""

import argparse
import json
import os
from collections import defaultdict


def fmt_rate(numer, denom):
    if denom <= 0:
        return "0.000000"
    return f"{(numer/denom):.6f}"


def parse_one(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", nargs="+", default=[os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "result", "ocr_eval_latest.json"))])
    args = parser.parse_args()

    datasets = [parse_one(p) for p in args.input if os.path.exists(p)]
    if not datasets:
        raise SystemExit("未找到可用输入，请先运行评测脚本生成结果 JSON。")

    rows_accum = {}

    def accumulate_field_stats(stats_obj):
        overall = stats_obj.get("__overall_field_accuracy__") if isinstance(stats_obj, dict) else None
        if overall:
            return overall.get("matched", 0), overall.get("total", 0)
        return 0, 0

    for data in datasets:
        cases = data.get("entries") or data.get("cases") or data.get("details") or []
        summary = data.get("summary", {})
        by_report_type = summary.get("by_report_type", {})
        # 逐条汇总 case 计数（适配 entries 结构）
        by_type_counts = defaultdict(lambda: {"total": 0, "ok": 0, "err": 0, "diff": 0})
        for c in cases:
            rtype = c.get("report_type", "?")
            by_type_counts[rtype]["total"] += 1
            st = c.get("status", "ok")
            if st == "ok":
                by_type_counts[rtype]["ok"] += 1
            else:
                by_type_counts[rtype]["err"] += 1
            if c.get("has_diff"):
                by_type_counts[rtype]["diff"] += 1

        # 从 by_report_type 抓字段准确率（优先），否则用总 summary 近似均分
        for rtype, cnts in by_type_counts.items():
            a = rows_accum.setdefault(rtype, {"total": 0, "ok": 0, "err": 0, "diff": 0, "matched": 0, "tf": 0})
            a["total"] += cnts["total"]
            a["ok"] += cnts["ok"]
            a["err"] += cnts["err"]
            a["diff"] += cnts["diff"]
            subtype = by_report_type.get(rtype)
            if isinstance(subtype, dict):
                m, t = accumulate_field_stats(subtype.get("__overall_field_accuracy__") and {"__overall_field_accuracy__": subtype.get("__overall_field_accuracy__")} or subtype.get("field_stats", {}))
                # 如果 subtype 中没有统计字段，回退 0
                a["matched"] += m
                a["tf"] += t
            else:
                # 回退用总 summary 的 overall 均分
                m, t = accumulate_field_stats(summary.get("field_stats", {}))
                types = max(1, len(by_type_counts))
                a["matched"] += m // types
                a["tf"] += t // types

    rows = []
    for rtype, a in rows_accum.items():
        rows.append((rtype, a["total"], a["ok"], a["err"], a["diff"], a["matched"], a["tf"]))

    # 打印与保存
    header = ["类型", "完成", "OK", "Error", "有差异", "字段准确率", "字段匹配"]
    lines = []
    lines.append("\t".join(header))
    for (rtype, total, ok, err, diff, matched, total_fields) in rows:
        acc = fmt_rate(matched, total_fields)
        lines.append("\t".join([
            rtype,
            f"{total}/{total}",
            str(ok),
            str(err),
            str(diff),
            acc,
            f"{matched}/{total_fields}",
        ]))

    out_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "result", "field_accuracy_report.txt"))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print("\n".join(lines))
    print(f"\n已保存: {out_path}")


if __name__ == "__main__":
    main()
