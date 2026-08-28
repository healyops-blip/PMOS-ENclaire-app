from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest
from pypdf import PdfWriter

from pomi_backend.services.ocr_prompts import PROMPT_VERSION, SCHEMA_VERSION, prompt_for, schema_for
from pomi_backend.services.ocr_provider import (
    OCRProviderError,
    OCRProviderRequest,
    Qwen3VLOCRProvider,
)


def _request(
    path: Path,
    kind: str = "lab_report",
    mime_type: str = "image/png",
) -> OCRProviderRequest:
    if not path.exists():
        path.write_bytes(b"image")
    return OCRProviderRequest(
        task_id="provider-task",
        material_type=kind,
        mime_type=mime_type,
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
    assert captured["body"]["response_format"] == {"type": "json_object"}
    assert captured["body"]["enable_thinking"] is False
    assert captured["body"]["max_tokens"] == 8192
    prompt = captured["body"]["messages"][0]["content"][0]["text"]
    assert "Required JSON Schema" in prompt
    assert '"additionalProperties":false' in prompt
    assert captured["body"]["model"] == "qwen3-vl-test"


def test_qwen_provider_renders_single_page_pdf_as_an_inline_image(tmp_path: Path) -> None:
    captured: dict = {}
    payload = {"draft": {"facility": None, "report_date": None, "items": []}, "fields": []}

    def handler(request: httpx.Request) -> httpx.Response:
        captured.update(json.loads(request.content))
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": json.dumps(payload)}}]},
        )

    pdf_path = tmp_path / "single-page.pdf"
    writer = PdfWriter()
    writer.add_blank_page(width=612, height=792)
    with pdf_path.open("wb") as stream:
        writer.write(stream)
    provider = Qwen3VLOCRProvider(
        api_base_url="https://provider.invalid/v1",
        api_key="unit-test-token",
        model="qwen3-vl-test",
        timeout_seconds=3,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )

    provider.recognize(_request(pdf_path, mime_type="application/pdf"))

    media_url = captured["messages"][0]["content"][1]["image_url"]["url"]
    assert media_url.startswith("data:image/png;base64,")
    assert "data:application/pdf" not in media_url


def test_qwen_provider_rejects_invalid_pdf_without_a_network_call(tmp_path: Path) -> None:
    calls = 0

    def handler(_: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(500)

    provider = Qwen3VLOCRProvider(
        api_base_url="https://provider.invalid/v1",
        api_key="unit-test-token",
        model="qwen3-vl-test",
        timeout_seconds=3,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    invalid = tmp_path / "invalid.pdf"
    invalid.write_bytes(b"not a pdf")

    with pytest.raises(OCRProviderError) as failure:
        provider.recognize(_request(invalid, mime_type="application/pdf"))

    assert failure.value.category == "file"
    assert failure.value.retryable is False
    assert calls == 0


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
    kinds = ("lab_report", "medical_order", "imaging_text_report")
    schemas = [schema_for(kind) for kind in kinds]
    assert all("fields" in schema["properties"] for schema in schemas)
    assert (
        len({json.dumps(schema["properties"]["draft"], sort_keys=True) for schema in schemas}) == 4
    )
    assert len({prompt_for(kind) for kind in kinds}) == 4
    assert set(schemas[0]["properties"]["draft"]["properties"]["items"]["items"]["properties"]) == {
        "item_name",
        "item_code",
        "raw_value",
        "numeric_value",
        "raw_unit",
        "normalized_unit",
        "reference_range_text",
        "reference_low",
        "reference_high",
    }
    assert set(
        schemas[1]["properties"]["draft"]["properties"]["orders"]["items"]["properties"]
    ) >= {"source_text", "drug_name", "dosage_value", "frequency", "route"}
    assert all(
        schema["properties"]["draft"].get("additionalProperties") is False for schema in schemas
    )


def test_medical_order_p0_fixture_covers_critical_fields() -> None:
    fixture_path = Path(__file__).parent / "fixtures" / "ocr" / "medical_order_p0.json"
    cases = json.loads(fixture_path.read_text(encoding="utf-8"))
    assert len(cases) >= 5
    assert all(
        {"drug_name", "dosage_value", "dosage_unit", "frequency"} <= set(case["expected"])
        for case in cases
    )
