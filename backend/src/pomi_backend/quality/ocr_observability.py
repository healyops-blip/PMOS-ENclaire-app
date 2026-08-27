"""Aggregate OCR operational signals without loading documents or medical fields."""

from __future__ import annotations

import math
from collections import Counter
from collections.abc import Iterable
from datetime import datetime
from typing import Any

from pomi_backend.db.models import OCRTask


def summarize_ocr_tasks(tasks: Iterable[OCRTask], *, now: datetime) -> dict[str, Any]:
    rows = list(tasks)
    statuses = Counter(task.status for task in rows)
    errors = Counter(task.error_category for task in rows if task.error_category)
    real_successes = [
        task
        for task in rows
        if task.result_source
        and task.result_source != "fallback"
        and task.status
        in {
            "pending_confirmation",
            "confirmed",
        }
    ]
    real_completed = [
        task
        for task in rows
        if task.result_source != "fallback" and task.status not in {"queued", "processing"}
    ]
    latencies = sorted(task.duration_ms for task in real_successes if task.duration_ms is not None)
    lease_anomalies = sum(
        1
        for task in rows
        if task.status == "processing"
        and task.lease_expires_at is not None
        and task.lease_expires_at <= now
    )
    return {
        "task_count": len(rows),
        "status_counts": dict(sorted(statuses.items())),
        "queue_backlog": statuses["queued"],
        "lease_anomalies": lease_anomalies,
        "real_model_success_rate": (
            round(len(real_successes) / len(real_completed), 6) if real_completed else None
        ),
        "real_model_latency_ms": {
            "sample_count": len(latencies),
            "p50": _percentile(latencies, 0.50),
            "p95": _percentile(latencies, 0.95),
        },
        "fallback_count_excluded": sum(task.result_source == "fallback" for task in rows),
        "error_distribution": dict(sorted(errors.items())),
    }


def _percentile(values: list[int], quantile: float) -> int | None:
    return values[max(0, math.ceil(len(values) * quantile) - 1)] if values else None
