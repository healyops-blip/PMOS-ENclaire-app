import os
import re
import json
import random


def normalize_prefix(s: str) -> str:
    return re.sub(r"^((备注|建议)[:：]\s*)+", "", str(s)).strip()


def main():
    samples = [
        "建议结合PCOS相关评估，按需随访",
        "备注：建议结合PCOS相关评估，按需随访",
        "备注:  建议结合PCOS相关评估",
        "建议：建议结合临床复查",
        "备注：备注：如为PCOS管理阶段，建议记录月经周期",
        "建议：备注：生活方式干预",
    ]
    for s in samples:
        cleaned = normalize_prefix(s)
        out = f"备注：{cleaned}"  # 引擎最终输出格式
        assert not re.search(r"备注[:：]\s*备注[:：]", out), f"dup prefix in: {out} (from {s})"
    print("Prefix normalization tests passed.")


if __name__ == "__main__":
    main()
