"""Run offline scoring or an explicitly authorized real Qwen3-VL evaluation."""

from __future__ import annotations

import argparse
import json
import os
import time
from datetime import UTC, datetime
from pathlib import Path

from pomi_backend.quality.ocr_evaluation import evaluate_ocr_quality
from pomi_backend.services.ocr_prompts import PROMPT_VERSION, SCHEMA_VERSION
from pomi_backend.services.ocr_provider import (
    OCRProviderError,
    OCRProviderRequest,
    Qwen3VLOCRProvider,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--predictions", type=Path)
    parser.add_argument("--run-qwen", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--records-output", type=Path)
    parser.add_argument("--enforce", action="store_true")
    args = parser.parse_args()
    dataset = json.loads(args.dataset.read_text(encoding="utf-8"))
    if args.run_qwen == (args.predictions is not None):
        parser.error("choose exactly one of --predictions or --run-qwen")
    predictions = (
        _run_qwen(args.dataset.parent, dataset)
        if args.run_qwen
        else json.loads(args.predictions.read_text(encoding="utf-8"))
    )
    outcome = evaluate_ocr_quality(dataset, predictions)
    versions = sorted(
        {
            (item.get("model"), item.get("prompt_version"), item.get("schema_version"))
            for item in predictions
            if item.get("source") != "fallback"
        }
    )
    artifact = {
        "executed_at": datetime.now(UTC).isoformat(),
        "execution_kind": "real_qwen3_vl" if args.run_qwen else "offline_predictions",
        "versions": [
            {"model": model, "prompt_version": prompt, "schema_version": schema}
            for model, prompt, schema in versions
        ],
        **outcome.report,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, ensure_ascii=False, indent=2) + "\n", "utf-8")
    if args.records_output is not None:
        args.records_output.parent.mkdir(parents=True, exist_ok=True)
        args.records_output.write_text(
            json.dumps(predictions, ensure_ascii=False, indent=2) + "\n", "utf-8"
        )
    print(json.dumps(artifact, ensure_ascii=False, indent=2))
    if args.enforce and not outcome.passed:
        raise SystemExit(1)


def _run_qwen(root: Path, dataset: list[dict]) -> list[dict]:
    api_key = os.getenv("POMI_OCR_API_KEY")
    if not api_key:
        raise SystemExit("POMI_OCR_API_KEY is required for --run-qwen")
    model = os.getenv("POMI_OCR_MODEL", "qwen3-vl-plus")
    provider = Qwen3VLOCRProvider(
        api_base_url=os.getenv(
            "POMI_OCR_API_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1"
        ),
        api_key=api_key,
        model=model,
        timeout_seconds=int(os.getenv("POMI_OCR_TIMEOUT_SECONDS", "90")),
    )
    records = []
    for sample in dataset:
        path = root / sample["file"]
        started = time.perf_counter()
        try:
            response = provider.recognize(
                OCRProviderRequest(
                    task_id=f"quality-{sample['sample_id']}",
                    material_type=sample["material_type"],
                    mime_type="image/png",
                    file_path=path,
                    file_name=path.name,
                    uploaded_at="2026-08-27T00:00:00+00:00",
                    file_hash=sample["sha256"],
                )
            )
            records.append(
                {
                    "sample_id": sample["sample_id"],
                    "source": response.source,
                    "status": "succeeded",
                    "duration_ms": round((time.perf_counter() - started) * 1000),
                    "model": model,
                    "prompt_version": PROMPT_VERSION,
                    "schema_version": SCHEMA_VERSION,
                    "payload": response.payload,
                }
            )
        except OCRProviderError as error:
            records.append(
                {
                    "sample_id": sample["sample_id"],
                    "source": "qwen3-vl",
                    "status": "failed",
                    "duration_ms": round((time.perf_counter() - started) * 1000),
                    "model": model,
                    "prompt_version": PROMPT_VERSION,
                    "schema_version": SCHEMA_VERSION,
                    "error_category": error.category,
                    "error_code": error.code,
                }
            )
    return records


if __name__ == "__main__":
    main()
