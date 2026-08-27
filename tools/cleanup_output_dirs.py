#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
清理仓库根目录下未使用的输出目录，仅保留 d:\\hackathon_26\\result。

会删除以下模式的目录：
  - result_*（除了 result 本身）
  - output, outputs, output_*（如果存在）

用法：
  python d:\\hackathon_26\\tools\\cleanup_output_dirs.py
"""

from __future__ import annotations

import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def should_delete(name: str) -> bool:
    if name == "result":
        return False
    if name.startswith("result_"):
        return True
    if name in {"output", "outputs"}:
        return True
    if name.startswith("output_"):
        return True
    return False

def main() -> None:
    for name in os.listdir(ROOT):
        p = os.path.join(ROOT, name)
        if os.path.isdir(p) and should_delete(name):
            try:
                shutil.rmtree(p)
                print(f"已删除目录: {p}")
            except Exception as e:  # noqa: BLE001
                print(f"删除失败: {p}: {e}")
    print("完成。仅保留了 d:\\hackathon_26\\result 作为输出目录。")

if __name__ == "__main__":
    main()
