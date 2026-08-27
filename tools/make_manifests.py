#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成两个便于人工查看的清单：
- d:\\hackathon_26\\result\\manifest_by_type.txt  按类型列出所有 case 及其 truth 文件位置
- d:\\hackathon_26\\result\\emr_failures.txt      汇总门诊病历_就诊记录评测失败的条目与错误原因

用法：
  python d:\\hackathon_26\\tools\\make_manifests.py
"""

from __future__ import annotations

import json
import os
from typing import Dict, Any

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULT_DIR = os.path.join(PROJECT_ROOT, "result")


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_text(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def build_manifest_by_type(truth_mapping_path: str) -> str:
    if not os.path.exists(truth_mapping_path):
        return "未找到 truth_mapping.json，请先生成数据集。\n"
    mapping: Dict[str, Dict[str, Any]] = read_json(truth_mapping_path)
    # 聚合
    by_type: Dict[str, Dict[str, Any]] = {}
    for image_rel, meta in mapping.items():
        rtype = meta.get("report_type", "?")
        group = by_type.setdefault(rtype, {})
        group[image_rel] = meta

    lines = []
    lines.append("类型\timage_rel\ttruth_file")
    for rtype in sorted(by_type.keys()):
        for image_rel, meta in sorted(by_type[rtype].items()):
            lines.append("\t".join([
                rtype,
                image_rel,
                str(meta.get("truth_file", "")),
            ]))
    return "\n".join(lines) + "\n"


def build_emr_failures(emr_eval_path: str) -> str:
    if not os.path.exists(emr_eval_path):
        return "未找到 EMR 评测结果 JSON。\n"
    data = read_json(emr_eval_path)
    entries = data.get("entries", [])
    if not entries:
        return "EMR 评测结果为空或无 entries。\n"
    lines = []
    lines.append("image_rel\tstatus\terror\tdoc_id\thospital\tvisit_date")
    for e in entries:
        if e.get("status") == "ok":
            # 只收集失败项，便于人工排查
            continue
        truth = e.get("truth") or {}
        lines.append("\t".join([
            str(e.get("image_rel", "")),
            str(e.get("status", "")),
            str(e.get("error", "")).replace("\n", " / ")[:300],
            str(truth.get("doc_id", "")),
            str(truth.get("hospital", "")),
            str(truth.get("visit_date", "")),
        ]))
    if len(lines) == 1:
        lines.append("无失败项。\n")
    return "\n".join(lines) + "\n"


def main() -> None:
    manifest_txt = build_manifest_by_type(os.path.join(RESULT_DIR, "truth_mapping.json"))
    write_text(os.path.join(RESULT_DIR, "manifest_by_type.txt"), manifest_txt)

    emr_txt = build_emr_failures(os.path.join(RESULT_DIR, "ocr_eval_latest_emr.json"))
    write_text(os.path.join(RESULT_DIR, "emr_failures.txt"), emr_txt)

    print("已生成：")
    print(os.path.join(RESULT_DIR, "manifest_by_type.txt"))
    print(os.path.join(RESULT_DIR, "emr_failures.txt"))


if __name__ == "__main__":
    main()
