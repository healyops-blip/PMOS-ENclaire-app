#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
清理 d:\\hackathon_26\\result 下当前不需要的子目录/文件，只保留在用的固定输出：
  - ocr_eval_latest_imaging.json
  - ocr_eval_latest_lab.json
  - ocr_eval_latest_rx.json
  - ocr_eval_latest_emr.json
  - field_accuracy_report.txt
  - truth_mapping.json（作为索引继续保留）
  - manifest_by_type.txt
  - emr_failures.txt

用法：
  python d:\\hackathon_26\\tools\\cleanup_results.py
"""

from __future__ import annotations

import os
import shutil

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULT_DIR = os.path.join(PROJECT_ROOT, "result")

KEEP_FILES = {
    "ocr_eval_latest_imaging.json",
    "ocr_eval_latest_lab.json",
    "ocr_eval_latest_rx.json",
    "ocr_eval_latest_emr.json",
    "field_accuracy_report.txt",
    "truth_mapping.json",
    "manifest_by_type.txt",
    "emr_failures.txt",
}


def main() -> None:
    if not os.path.isdir(RESULT_DIR):
        print(f"结果目录不存在: {RESULT_DIR}")
        return
    for name in os.listdir(RESULT_DIR):
        p = os.path.join(RESULT_DIR, name)
        if name in KEEP_FILES:
            continue
        try:
            if os.path.isdir(p):
                shutil.rmtree(p)
            else:
                os.remove(p)
            print(f"已删除: {p}")
        except Exception as e:  # noqa: BLE001
            print(f"删除失败: {p}: {e}")
    print("清理完成。保留文件:")
    for k in sorted(KEEP_FILES):
        print(os.path.join(RESULT_DIR, k))


if __name__ == "__main__":
    main()
