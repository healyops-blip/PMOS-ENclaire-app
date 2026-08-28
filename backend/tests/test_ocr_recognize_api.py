from __future__ import annotations

from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image
from pytest import MonkeyPatch

from pomi_backend.db.models import OCRTask
from pomi_backend.services.ocr_provider import OCRProviderResponse


def _headers(client: TestClient, account_name: str) -> dict[str, str]:
    password = "RecognizePass123"
    assert (
        client.post(
            "/api/auth/register",
            json={"account_name": account_name, "password": password},
        ).status_code
        == 201
    )
    login = client.post(
        "/api/auth/login",
        json={"account_name": account_name, "password": password},
    )
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def _image_bytes() -> bytes:
    output = BytesIO()
    Image.new("RGB", (40, 20), color=(248, 244, 252)).save(output, format="PNG")
    return output.getvalue()


def _fields(value, path: str = "") -> list[dict]:
    if isinstance(value, dict):
        return [
            field
            for key, child in value.items()
            for field in _fields(child, f"{path}.{key}" if path else key)
        ]
    if isinstance(value, list):
        return [
            field
            for index, child in enumerate(value)
            for field in _fields(child, f"{path}[{index}]")
        ]
    return [
        {
            "path": path,
            "source_text": value if isinstance(value, str) else None,
            "value": value,
            "confidence": 0.96,
            "uncertainty_reason": None,
            "source_region": None,
        }
    ]


def test_sync_recognize_persists_confirmable_result_and_reuses_it(
    api_client: TestClient,
    monkeypatch: MonkeyPatch,
) -> None:
    draft = {
        "hospital_name": "Pomi Demo Hospital",
        "sample_date": "2026-08-20",
        "report_date": "2026-08-21",
        "items": [
            {
                "item_name": "睾酮",
                "item_code": None,
                "raw_value": "1.8",
                "numeric_value": 1.8,
                "raw_unit": "nmol/L",
                "normalized_unit": "nmol/L",
                "reference_range_text": "0.3-2.4",
                "reference_low": 0.3,
                "reference_high": 2.4,
            }
        ],
    }

    class FakeProvider:
        calls = 0

        def __init__(self, **_kwargs) -> None:
            pass

        def recognize(self, request) -> OCRProviderResponse:
            type(self).calls += 1
            with api_client.app.state.session_factory() as session:
                claimed = session.get(OCRTask, request.task_id)
                assert claimed is not None
                assert claimed.status == "processing"
                assert claimed.lease_owner == f"sync:{request.task_id}"
                assert claimed.provider_call_started_at is not None
            payload = {"draft": draft, "fields": _fields(draft)}
            return OCRProviderResponse(
                raw_response={"fake": True},
                payload=payload,
                source="fake-qwen3-vl",
            )

    monkeypatch.setattr("pomi_backend.api.ocr.Qwen3VLOCRProvider", FakeProvider)
    headers = _headers(api_client, "sync-ocr-owner")
    request_headers = {
        **headers,
        "Idempotency-Key": "sync-recognize-0001",
        "X-External-Processing-Consent-Version": "pomi-external-processing-v1",
    }

    response = api_client.post(
        "/api/ocr/recognize",
        headers=request_headers,
        data={"material_type": "lab_report", "prompt_version": "pomi-ocr-v1"},
        files={"file": ("lab.png", _image_bytes(), "image/png")},
    )
    assert response.status_code == 200, response.text
    recognized = response.json()["data"]
    assert recognized["material_type"] == "lab_report"
    assert recognized["result_source"] == "fake-qwen3-vl"
    assert recognized["draft"] == draft
    assert recognized["task_id"]
    assert recognized["result_id"]
    assert recognized["document_revision_id"]

    task = api_client.get(f"/api/ocr/tasks/{recognized['task_id']}", headers=headers)
    assert task.status_code == 200
    assert task.json()["data"]["status"] == "pending_confirmation"

    confirmed = api_client.post(
        f"/api/ocr/tasks/{recognized['task_id']}/confirm",
        headers=headers,
        json={
            "result_id": recognized["result_id"],
            "expected_revision_id": recognized["document_revision_id"],
            "sample_date": "2026-08-20",
            "report_date": "2026-08-21",
            "items": [
                {
                    "source_index": 0,
                    "name": "睾酮",
                    "value": "1.8",
                    "unit": "nmol/L",
                    "reference_range": "0.3-2.4",
                }
            ],
        },
    )
    assert confirmed.status_code == 200, confirmed.text
    assert confirmed.json()["data"]["status"] == "confirmed"
    assert len(confirmed.json()["data"]["created_resource_ids"]) == 1

    documents = api_client.get("/api/documents", headers=headers)
    assert documents.status_code == 200
    listed = documents.json()["data"]["items"][0]
    assert listed["latest_ocr_task_id"] == recognized["task_id"]
    assert listed["latest_ocr_status"] == "confirmed"
    assert listed["latest_ocr_result_source"] == "fake-qwen3-vl"
    dashboard = api_client.get("/api/dashboard", headers=headers)
    assert dashboard.status_code == 200
    assert dashboard.json()["data"]["document_summary"]["data"] == {
        "confirmed": 1,
        "total": 1,
    }

    repeated = api_client.post(
        "/api/ocr/recognize",
        headers=request_headers,
        data={"material_type": "lab_report", "prompt_version": "pomi-ocr-v1"},
        files={"file": ("lab.png", _image_bytes(), "image/png")},
    )
    assert repeated.status_code == 200, repeated.text
    assert repeated.json()["data"]["task_id"] == recognized["task_id"]
    assert repeated.json()["data"]["result_id"] == recognized["result_id"]
    assert FakeProvider.calls == 1
