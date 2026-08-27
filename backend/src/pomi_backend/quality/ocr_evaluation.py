"""Deterministic OCR quality scoring with fallback results excluded."""

from __future__ import annotations

import math
from collections import Counter, defaultdict
from dataclasses import dataclass
from typing import Any

from jsonschema import ValidationError, validate

from pomi_backend.services.ocr_prompts import schema_for

QUALITY_GATES = {"schema_pass_rate": 1.0, "P0": 0.95, "P1": 0.90, "P2": 0.80}


@dataclass(frozen=True, slots=True)
class EvaluationOutcome:
    report: dict[str, Any]
    passed: bool


def evaluate_ocr_quality(
    dataset: list[dict[str, Any]], predictions: list[dict[str, Any]]
) -> EvaluationOutcome:
    """Score genuine model records; fixed fallback records never enter denominators."""

    samples = {sample["sample_id"]: sample for sample in dataset}
    qwen_records = [record for record in predictions if record.get("source") != "fallback"]
    records = {record["sample_id"]: record for record in qwen_records}
    counts = Counter(sample["material_type"] for sample in dataset)
    evaluated_counts: Counter[str] = Counter()
    successes: Counter[str] = Counter()
    payload_successes: Counter[str] = Counter()
    errors: Counter[str] = Counter()
    errors_by_type: defaultdict[str, Counter[str]] = defaultdict(Counter)
    schema_passes = 0
    field_total: Counter[str] = Counter()
    field_correct: Counter[str] = Counter()
    critical_failures: list[dict[str, str]] = []
    latencies: list[int] = []

    for sample_id, record in records.items():
        sample = samples.get(sample_id)
        if sample is None:
            errors["unknown_sample"] += 1
            continue
        material_type = sample["material_type"]
        evaluated_counts[material_type] += 1
        if isinstance(record.get("duration_ms"), int):
            latencies.append(record["duration_ms"])
        if record.get("status") != "succeeded" or not isinstance(record.get("payload"), dict):
            category = str(record.get("error_category") or "model_failure")
            errors[category] += 1
            errors_by_type[material_type][category] += 1
            continue
        payload = record["payload"]
        payload_successes[material_type] += 1
        try:
            validate(payload, schema_for(material_type))
            schema_passes += 1
        except ValidationError:
            errors["schema_invalid"] += 1
            errors_by_type[material_type]["schema_invalid"] += 1
            continue
        successes[material_type] += 1
        for field in sample["gold_fields"]:
            priority = field["priority"]
            field_total[priority] += 1
            actual = _resolve(payload, field["path"])
            accepted = [field["expected"], *field.get("allowed_values", [])]
            correct = any(_normalize(actual) == _normalize(value) for value in accepted)
            if correct:
                field_correct[priority] += 1
            elif field.get("critical", False):
                critical_failures.append(
                    {"sample_id": sample_id, "path": field["path"], "priority": priority}
                )

    evaluated_total = sum(evaluated_counts.values())
    payload_successful_total = sum(payload_successes.values())
    field_accuracy = {
        priority: _ratio(field_correct[priority], field_total[priority])
        for priority in ("P0", "P1", "P2")
    }
    per_type = {
        material_type: {
            "dataset_samples": counts[material_type],
            "evaluated_qwen_samples": evaluated_counts[material_type],
            "succeeded": successes[material_type],
            "success_rate": _ratio(successes[material_type], evaluated_counts[material_type]),
            "error_distribution": dict(sorted(errors_by_type[material_type].items())),
        }
        for material_type in sorted(counts)
    }
    report = {
        "dataset_sample_count": len(dataset),
        "qwen_sample_count": evaluated_total,
        "fallback_records_excluded": len(predictions) - len(qwen_records),
        "schema_pass_rate": _ratio(schema_passes, payload_successful_total),
        "field_accuracy": field_accuracy,
        "critical_failure_count": len(critical_failures),
        "critical_failures": critical_failures,
        "latency_ms": {
            "sample_count": len(latencies),
            "p50": _percentile(latencies, 0.50),
            "p95": _percentile(latencies, 0.95),
        },
        "per_material_type": per_type,
        "error_distribution": dict(sorted(errors.items())),
    }
    complete = evaluated_total == len(dataset) and all(value >= 10 for value in counts.values())
    passed = (
        complete
        and report["schema_pass_rate"] >= QUALITY_GATES["schema_pass_rate"]
        and all(field_accuracy[p] >= QUALITY_GATES[p] for p in ("P0", "P1", "P2"))
        and not critical_failures
    )
    report["gates"] = {"thresholds": QUALITY_GATES, "dataset_complete": complete, "passed": passed}
    return EvaluationOutcome(report=report, passed=passed)


def _resolve(value: Any, path: str) -> Any:
    current = value
    for part in path.split("."):
        try:
            current = current[int(part)] if isinstance(current, list) else current[part]
        except (KeyError, IndexError, TypeError, ValueError):
            return None
    return current


def _normalize(value: Any) -> Any:
    if isinstance(value, str):
        return " ".join(value.casefold().split()).replace("％", "%")
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, list):
        return [_normalize(item) for item in value]
    if isinstance(value, dict):
        return {key: _normalize(item) for key, item in sorted(value.items())}
    return value


def _ratio(numerator: int, denominator: int) -> float:
    return round(numerator / denominator, 6) if denominator else 0.0


def _percentile(values: list[int], quantile: float) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, math.ceil(len(ordered) * quantile) - 1)
    return ordered[index]
