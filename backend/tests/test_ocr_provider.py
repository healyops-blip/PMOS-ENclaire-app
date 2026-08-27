from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest
from jsonschema import validate

from pomi_backend.services.ocr_prompts import PROMPT_VERSION, SCHEMA_VERSION, prompt_for, schema_for
from pomi_backend.services.ocr_provider import (
    OCRProviderError,
    OCRProviderRequest,
    Qwen3VLOCRProvider,
)


def _request(path: Path, kind: str = "lab_report") -> OCRProviderRequest:
    path.write_bytes(b"image")
    return OCRProviderRequest(
        task_id="provider-task",
        material_type=kind,
        mime_type="image/png",
        file_path=path,
        file_name="lab.png",
        uploaded_at="2026-08-27T10:00:00+00:00",
        file_hash="safe-file-hash",
    )


def test_qwen_provider_builds_structured_request_without_exposing_key(tmp_path: Path) -> None:
    captured: dict = {}
    payload = {
        "draft": {"facility": None, "report_date": None, "items": []},
        "fields": [],
    }

    def handler(request: httpx.Request) -> httpx.Response:
        captured["authorization"] = request.headers["Authorization"]
        captured["idempotency"] = request.headers["Idempotency-Key"]
        captured["body"] = json.loads(request.content)
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": json.dumps(payload)}}]},
        )

    provider = Qwen3VLOCRProvider(
        api_base_url="https://provider.invalid/v1",
        api_key="unit-test-token",
        model="qwen3-vl-test",
        timeout_seconds=3,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    response = provider.recognize(_request(tmp_path / "lab.png"))

    assert response.payload == payload
    assert captured["authorization"] == "Bearer unit-test-token"
    assert captured["idempotency"] == "provider-task"
    assert captured["body"]["response_format"]["json_schema"]["strict"] is True
    assert captured["body"]["model"] == "qwen3-vl-test"


def test_qwen_provider_configuration_and_temporary_errors_are_typed(tmp_path: Path) -> None:
    unconfigured = Qwen3VLOCRProvider(
        api_base_url="https://provider.invalid/v1",
        api_key=None,
        model="qwen3-vl-test",
        timeout_seconds=3,
    )
    with pytest.raises(OCRProviderError) as missing:
        unconfigured.recognize(_request(tmp_path / "missing.png"))
    assert missing.value.code == "OCR_NOT_CONFIGURED"
    assert missing.value.retryable is False

    unavailable = Qwen3VLOCRProvider(
        api_base_url="https://provider.invalid/v1",
        api_key="unit-test-token",
        model="qwen3-vl-test",
        timeout_seconds=3,
        client=httpx.Client(transport=httpx.MockTransport(lambda _: httpx.Response(503))),
    )
    with pytest.raises(OCRProviderError) as temporary:
        unavailable.recognize(_request(tmp_path / "unavailable.png"))
    assert temporary.value.category == "provider_unavailable"
    assert temporary.value.retryable is True


def test_all_material_prompts_and_schemas_are_versioned_and_distinct() -> None:
    assert PROMPT_VERSION == "pomi-ocr-v1"
    assert SCHEMA_VERSION == "pomi-ocr-schema-v1"
    kinds = ("lab_report", "medical_order", "imaging_text_report", "outpatient_record")
    schemas = [schema_for(kind) for kind in kinds]
    assert all("fields" in schema["properties"] for schema in schemas)
    assert (
        len({json.dumps(schema["properties"]["draft"], sort_keys=True) for schema in schemas}) == 4
    )
    assert len({prompt_for(kind) for kind in kinds}) == 4


def test_medical_order_p0_fixture_matches_single_response_schema() -> None:
    fixture_path = Path(__file__).parent / "fixtures" / "ocr" / "medical_order_p0.json"
    cases = json.loads(fixture_path.read_text(encoding="utf-8"))
    assert len(cases) >= 5
    medication = {
        "drug_name": "盐酸二甲双胍",
        "specification": "500 mg",
        "dosage_value": 500,
        "dosage_unit": "mg",
        "frequency": "每日2次",
        "course": "30天",
        "route": "口服",
        "instructions": "随餐",
        "raw_order_text": cases[0]["source_text"],
        "explicitly_stopped": False,
    }
    payload = {
        "draft": {
            "facility": "Pomi Hospital",
            "order_date": "2026-08-27",
            "order_text": cases[0]["source_text"],
            "medications": [medication],
        },
        "fields": [
            {
                "path": "medications[0].drug_name",
                "source_text": cases[0]["source_text"],
                "value": medication["drug_name"],
                "confidence": 0.98,
            }
        ],
    }
    validate(payload, schema_for("medical_order"))
    assert all(
        {"drug_name", "dosage_value", "dosage_unit", "frequency"} <= set(case["expected"])
        for case in cases
    )
