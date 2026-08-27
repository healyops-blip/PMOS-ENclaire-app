#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
Call a multimodal LLM to extract structured OCR JSON from generated medical
report images, then compare the OCR JSON against this project's truth JSON.

Examples:
  python d:\hackathon_26\tools\ocr_llm_eval.py --result-dir d:\hackathon_26\result --limit 3
  python d:\hackathon_26\tools\ocr_llm_eval.py --dry-run --limit 2
"""

from __future__ import annotations

import argparse
import base64
import copy
import json
import mimetypes
import os
import re
import sys
import time
import traceback
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime
from typing import Any, Dict, Iterable, List, Optional, Tuple


PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_RESULT_DIR = os.path.join(PROJECT_ROOT, "result")
DEFAULT_ENDPOINT = "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions"
DEFAULT_MODEL = "qwen3.8-max"

TOP_LEVEL_FIELDS = [
    "doc_id",
    "hospital",
    "department",
    "visit_date",
    "diagnosis_summary",
    "medical_advice",
    "original_file_name",
]
REQUIRED_SCHEMA_FIELDS = [
    "doc_id",
    "hospital",
    "department",
    "visit_date",
    "diagnosis_summary",
    "medical_advice",
    "examinations",
    "medication_suggestions",
    "original_file_name",
]
EXAM_FIELDS = ["item_name", "value", "unit", "reference_range", "abnormal", "source_text"]
MED_FIELDS = ["drug_name", "dosage", "frequency", "duration", "instruction", "source_text"]


OCR_PROMPT = r'''你是一个医疗票据/报告 OCR 信息抽取模型。请从输入图片中识别文字，并严格按照指定 JSON 结构输出结果，用于和标准 truth JSON 对齐。

重要规则：
1. 只输出 JSON，不要输出解释、Markdown、代码块或多余文本。
2. 字段名必须完全一致，不要新增字段，不要删除字段。
3. 所有数值统一输出为字符串，例如 "37.5"、"31*18*33"、"134/96"。
4. 如果图片中没有对应内容，字符串字段输出 ""，数组字段输出 []。
5. 不要编造图片中不存在的信息；但本数据集若未显示科室且无法判断，department 默认填 "生殖科"。
6. original_file_name 如果无法从输入获得，填 ""。
7. abnormal 字段输出布尔值 true 或 false。
8. 日期按图片中的格式输出，通常为 "YYYY-MM-DD"。
9. 医院名称尽量完整保留中文和英文，例如 "长沙连心医院Lianxin Hospital Changsha"。
10. 对影像报告中的卵巢测量和基础卵泡，source_text 必须保留完整原句。
11. 对处方中的每个药品，source_text 必须包含“药品、用法、用量、疗程、总量”等信息。

请先判断报告类型：影像文字报告、化验_检测报告、医嘱_处方、门诊病历_就诊记录。

按以下 JSON schema 输出：
{
  "doc_id": "",
  "hospital": "",
  "department": "",
  "visit_date": "",
  "diagnosis_summary": "",
  "medical_advice": "",
  "examinations": [],
  "medication_suggestions": [],
  "original_file_name": ""
}

影像文字报告：examinations 尽量包含右卵巢、右侧基础卵泡、左卵巢、左侧基础卵泡、盆腔积液。卵巢 value 为 "长*宽*高"，unit="mm"；基础卵泡 value 只保留数字，unit="个"；source_text 保留完整原句。
化验_检测报告：按表格逐行抽取 item_name、value、unit、reference_range、abnormal，通常 13 项。
医嘱_处方：examinations=[]；药品放入 medication_suggestions，每个药品包含 drug_name、dosage、frequency、duration、instruction、source_text。
门诊病历_就诊记录：examinations 只包含体温、心率、血压；medication_suggestions=[]。

现在请根据输入图片输出严格 JSON。'''


def load_dotenv(path: str) -> None:
    if not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def get_api_key(explicit_key_name: Optional[str]) -> str:
    candidates = [explicit_key_name] if explicit_key_name else []
    candidates += ["API_KEY", "ALIYUN_API_KEY", "QWEN_API_KEY", "TOKEN_PLAN_API_KEY"]
    for key in candidates:
        if key and os.environ.get(key):
            return os.environ[key]
    raise RuntimeError("API key not found. Put API_KEY=... in d:\\hackathon_26\\.env")


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, data: Any) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def normalize_path(path: str) -> str:
    return path.replace("\\", os.sep).replace("/", os.sep)


def iter_cases(result_dir: str, limit: Optional[int], report_type: Optional[str]) -> Iterable[Dict[str, Any]]:
    mapping = read_json(os.path.join(result_dir, "truth_mapping.json"))
    count = 0
    for image_rel, meta in mapping.items():
        current_type = meta.get("report_type", "")
        if report_type and current_type != report_type:
            continue
        truth_rel = meta.get("truth_file")
        if not truth_rel:
            continue
        truth_path = os.path.join(result_dir, normalize_path(truth_rel))
        image_path = os.path.join(result_dir, normalize_path(image_rel))
        if not os.path.exists(image_path):
            image_path = os.path.join(os.path.dirname(truth_path), os.path.basename(truth_path).replace(".json", ".jpg"))
        yield {
            "image_rel": image_rel,
            "truth_rel": truth_rel,
            "report_type": current_type,
            "image_path": image_path,
            "truth_path": truth_path,
            "missing": not (os.path.exists(image_path) and os.path.exists(truth_path)),
            "truth": read_json(truth_path) if os.path.exists(truth_path) else None,
        }
        count += 1
        if limit is not None and count >= limit:
            break


def image_to_data_url(image_path: str) -> str:
    mime, _ = mimetypes.guess_type(image_path)
    if not mime:
        mime = "image/png" if image_path.lower().endswith(".png") else "image/jpeg"
    with open(image_path, "rb") as f:
        encoded = base64.b64encode(f.read()).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def call_model(endpoint: str, api_key: str, model: str, image_path: str, timeout: int, retries: int, retry_sleep: float) -> Tuple[str, Dict[str, Any]]:
    body = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": OCR_PROMPT},
                    {"type": "image_url", "image_url": {"url": image_to_data_url(image_path)}},
                ],
            }
        ],
    }
    payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    last_error: Optional[BaseException] = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(endpoint, data=payload, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                response = json.loads(resp.read().decode("utf-8", errors="replace"))
            return response["choices"][0]["message"]["content"], response
        except urllib.error.HTTPError as e:
            last_error = RuntimeError(f"HTTP {e.code}: {e.read().decode('utf-8', errors='replace')}")
        except Exception as e:  # noqa: BLE001
            last_error = e
        if attempt < retries:
            time.sleep(retry_sleep * (attempt + 1))
    raise RuntimeError(f"model call failed: {last_error}")


def extract_json(text: str) -> Dict[str, Any]:
    text = text.strip()
    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, flags=re.S | re.I)
    if fenced:
        text = fenced.group(1).strip()
    if not text.startswith("{"):
        start, end = text.find("{"), text.rfind("}")
        if start >= 0 and end > start:
            text = text[start : end + 1]
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise ValueError("model output JSON is not an object")
    return parsed


def ensure_schema(obj: Dict[str, Any]) -> Dict[str, Any]:
    result = dict(obj)
    for key in REQUIRED_SCHEMA_FIELDS:
        result.setdefault(key, [] if key in {"examinations", "medication_suggestions"} else "")
    if not isinstance(result.get("examinations"), list):
        result["examinations"] = []
    if not isinstance(result.get("medication_suggestions"), list):
        result["medication_suggestions"] = []
    return result


def postprocess_ocr(ocr: Dict[str, Any], image_path: str, fill_original_file_name: bool) -> Dict[str, Any]:
    result = ensure_schema(ocr)
    if fill_original_file_name and not str(result.get("original_file_name", "")).strip():
        result["original_file_name"] = os.path.basename(image_path)
    return result


def normalize_scalar(value: Any, field_name: str = "") -> Any:
    if isinstance(value, bool):
        return value
    if value is None:
        return ""
    if isinstance(value, (int, float)):
        if isinstance(value, float) and value.is_integer():
            return str(int(value))
        return str(value)
    text = str(value).strip()
    if field_name == "value":
        text = text.replace("﹡", "*").replace("＊", "*").replace("×", "*")
    if field_name in {"doc_id", "visit_date", "value", "unit", "reference_range"}:
        text = re.sub(r"\s+", "", text)
    else:
        text = re.sub(r"\s+", " ", text)
    return text.strip()


def add_field_stat(stats: Dict[str, int], ok: bool) -> None:
    stats["total"] += 1
    stats["matched" if ok else "mismatched"] += 1


def list_to_map(items: Any, key_field: str) -> Tuple[Dict[str, Dict[str, Any]], int]:
    mapped: Dict[str, Dict[str, Any]] = {}
    duplicate_count = 0
    if not isinstance(items, list):
        return mapped, duplicate_count
    for idx, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        key = normalize_scalar(item.get(key_field, ""), key_field) or f"__index_{idx}"
        if key in mapped:
            duplicate_count += 1
            key = f"{key}__dup_{idx}"
        mapped[key] = item
    return mapped, duplicate_count


def compare_named_list(expected_items: Any, actual_items: Any, key_field: str, fields: List[str], list_name: str, stats: Dict[str, Dict[str, int]]) -> Dict[str, Any]:
    expected_map, expected_dups = list_to_map(expected_items, key_field)
    actual_map, actual_dups = list_to_map(actual_items, key_field)
    expected_keys, actual_keys = set(expected_map), set(actual_map)
    missing_keys = sorted(expected_keys - actual_keys)
    extra_keys = sorted(actual_keys - expected_keys)
    stats[list_name]["expected_items"] += len(expected_map)
    stats[list_name]["actual_items"] += len(actual_map)
    stats[list_name]["missing_items"] += len(missing_keys)
    stats[list_name]["extra_items"] += len(extra_keys)
    stats[list_name]["duplicate_expected_items"] += expected_dups
    stats[list_name]["duplicate_actual_items"] += actual_dups
    item_diffs = []
    for key in sorted(expected_keys & actual_keys):
        field_diffs = []
        for field in fields:
            ok = normalize_scalar(expected_map[key].get(field, ""), field) == normalize_scalar(actual_map[key].get(field, ""), field)
            add_field_stat(stats[f"{list_name}.{field}"], ok)
            if not ok:
                field_diffs.append({"field": field, "truth": expected_map[key].get(field, ""), "ocr": actual_map[key].get(field, "")})
        if field_diffs:
            item_diffs.append({"key": key, "field_diffs": field_diffs})
    return {"missing_keys": missing_keys, "extra_keys": extra_keys, "item_diffs": item_diffs}


def compare_truth(truth: Dict[str, Any], ocr: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Dict[str, int]]]:
    truth = ensure_schema(truth)
    ocr = ensure_schema(ocr)
    stats: Dict[str, Dict[str, int]] = defaultdict(lambda: defaultdict(int))
    top_level_diffs = []
    for field in TOP_LEVEL_FIELDS:
        ok = normalize_scalar(truth.get(field, ""), field) == normalize_scalar(ocr.get(field, ""), field)
        add_field_stat(stats[f"top.{field}"], ok)
        if not ok:
            top_level_diffs.append({"field": field, "truth": truth.get(field, ""), "ocr": ocr.get(field, "")})
    exam_diff = compare_named_list(truth.get("examinations", []), ocr.get("examinations", []), "item_name", EXAM_FIELDS, "examinations", stats)
    med_diff = compare_named_list(truth.get("medication_suggestions", []), ocr.get("medication_suggestions", []), "drug_name", MED_FIELDS, "medication_suggestions", stats)
    return {"top_level_diffs": top_level_diffs, "examinations": exam_diff, "medication_suggestions": med_diff}, stats


def merge_stats(target: Dict[str, Dict[str, int]], source: Dict[str, Dict[str, int]]) -> None:
    for group, values in source.items():
        for key, value in values.items():
            target[group][key] += value


def summarize_stats(stats: Dict[str, Dict[str, int]]) -> Dict[str, Any]:
    summary: Dict[str, Any] = {}
    total_fields = matched_fields = 0
    for group, values in sorted(stats.items()):
        item = dict(values)
        if "total" in item:
            total = item.get("total", 0)
            matched = item.get("matched", 0)
            item["accuracy"] = round(matched / total, 6) if total else None
            total_fields += total
            matched_fields += matched
        summary[group] = item
    summary["__overall_field_accuracy__"] = {
        "total": total_fields,
        "matched": matched_fields,
        "mismatched": total_fields - matched_fields,
        "accuracy": round(matched_fields / total_fields, 6) if total_fields else None,
    }
    return summary


def has_any_diff(diff: Dict[str, Any]) -> bool:
    return bool(
        diff.get("top_level_diffs")
        or diff.get("examinations", {}).get("missing_keys")
        or diff.get("examinations", {}).get("extra_keys")
        or diff.get("examinations", {}).get("item_diffs")
        or diff.get("medication_suggestions", {}).get("missing_keys")
        or diff.get("medication_suggestions", {}).get("extra_keys")
        or diff.get("medication_suggestions", {}).get("item_diffs")
    )


def default_output_path(result_dir: str, model: str) -> str:
    return os.path.join(result_dir, f"ocr_eval_{re.sub(r'[^A-Za-z0-9_.-]+', '_', model)}.json")


def run(args: argparse.Namespace) -> int:
    load_dotenv(args.env)
    api_key = None if args.dry_run else get_api_key(args.api_key_env)
    cases = list(iter_cases(args.result_dir, args.limit, args.report_type))
    output = args.output or default_output_path(args.result_dir, args.model)
    aggregate_stats: Dict[str, Dict[str, int]] = defaultdict(lambda: defaultdict(int))
    by_report_type: Dict[str, Dict[str, Dict[str, int]]] = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))
    entries: List[Dict[str, Any]] = []
    status_counter: Counter[str] = Counter()
    diff_cases = 0
    print(f"开始评测: cases={len(cases)}, model={args.model}, dry_run={args.dry_run}")
    print(f"结果将写入: {output}")
    for idx, case in enumerate(cases, 1):
        report_type = case.get("report_type") or "UNKNOWN"
        print(f"[{idx}/{len(cases)}] {case.get('image_rel')} ({report_type})")
        entry: Dict[str, Any] = {"image_rel": case.get("image_rel"), "truth_rel": case.get("truth_rel"), "report_type": report_type}
        if case.get("missing"):
            entry.update({"status": "missing_file", "error": {"image_path": case.get("image_path"), "truth_path": case.get("truth_path")}})
            status_counter["missing_file"] += 1
            entries.append(entry)
            continue
        truth = case["truth"]
        raw_text = ""
        raw_response = None
        try:
            if args.dry_run:
                ocr = copy.deepcopy(truth)
                raw_text = json.dumps(ocr, ensure_ascii=False)
            else:
                raw_text, raw_response = call_model(args.endpoint, api_key or "", args.model, case["image_path"], args.timeout, args.retries, args.retry_sleep)
                ocr = extract_json(raw_text)
            ocr = postprocess_ocr(ocr, case["image_path"], not args.no_fill_original_file_name)
            diff, case_stats = compare_truth(truth, ocr)
            merge_stats(aggregate_stats, case_stats)
            merge_stats(by_report_type[report_type], case_stats)
            has_diff = has_any_diff(diff)
            diff_cases += int(has_diff)
            entry.update({"status": "ok", "has_diff": has_diff, "truth": truth, "ocr": ocr, "diff": diff})
            if args.include_raw_response:
                entry["raw_model_text"] = raw_text
                if raw_response is not None:
                    entry["raw_response"] = raw_response
            status_counter["ok"] += 1
        except Exception as e:  # noqa: BLE001
            entry.update({"status": "error", "error": str(e), "traceback": traceback.format_exc(limit=5), "raw_model_text": raw_text, "truth": truth})
            status_counter["error"] += 1
        entries.append(entry)
        if args.sleep > 0 and idx < len(cases):
            time.sleep(args.sleep)
    aggregate_summary = summarize_stats(aggregate_stats)
    ok_cases = status_counter.get("ok", 0)
    result = {
        "meta": {
            "started_at": datetime.now().isoformat(timespec="seconds"),
            "model": args.model,
            "endpoint": args.endpoint,
            "result_dir": os.path.abspath(args.result_dir),
            "prompt": OCR_PROMPT,
            "dry_run": args.dry_run,
        },
        "summary": {
            "case_count": len(cases),
            "ok_cases": ok_cases,
            "error_cases": status_counter.get("error", 0),
            "missing_file_cases": status_counter.get("missing_file", 0),
            "diff_cases": diff_cases,
            "exact_case_match_rate": round((ok_cases - diff_cases) / ok_cases, 6) if ok_cases else None,
            "field_stats": aggregate_summary,
            "by_report_type": {rt: summarize_stats(stats) for rt, stats in sorted(by_report_type.items())},
        },
        "entries": entries,
    }
    write_json(output, result)
    overall = aggregate_summary.get("__overall_field_accuracy__", {})
    print("\n评测完成")
    print(f"  输出文件: {output}")
    print(f"  OK cases: {ok_cases}/{len(cases)}")
    print(f"  Diff cases: {diff_cases}/{ok_cases}")
    print(f"  Overall field accuracy: {overall.get('accuracy')} ({overall.get('matched')}/{overall.get('total')})")
    return 0 if status_counter.get("error", 0) == 0 and status_counter.get("missing_file", 0) == 0 else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Call qwen3.8-max OCR and compare against project truth JSON")
    parser.add_argument("--result-dir", default=DEFAULT_RESULT_DIR)
    parser.add_argument("--output", default=None)
    parser.add_argument("--env", default=os.path.join(PROJECT_ROOT, ".env"))
    parser.add_argument("--api-key-env", default=None)
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--report-type", default=None, choices=["影像文字报告", "化验_检测报告", "医嘱_处方", "门诊病历_就诊记录"])
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--retry-sleep", type=float, default=2.0)
    parser.add_argument("--sleep", type=float, default=0.0)
    parser.add_argument("--include-raw-response", action="store_true")
    parser.add_argument("--no-fill-original-file-name", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    return run(build_parser().parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())