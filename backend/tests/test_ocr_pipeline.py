from __future__ import annotations

from datetime import timedelta
from io import BytesIO
from typing import Any

from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy.orm import Session, sessionmaker

from pomi_backend.db.models import OCRResult, OCRTask
from pomi_backend.db.models.auth import utc_now
from pomi_backend.services.ocr_provider import (
    OCRProviderError,
    OCRProviderRequest,
    OCRProviderResponse,
)
from pomi_backend.worker.ocr import OCRWorker


def _headers(client: TestClient, name: str) -> dict[str, str]:
    password = "OcrPipelinePass123"
    response = client.post("/api/auth/register", json={"account_name": name, "password": password})
    assert response.status_code == 201
    login = client.post("/api/auth/login", json={"account_name": name, "password": password})
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def _image(index: int = 0) -> bytes:
    output = BytesIO()
    Image.new("RGB", (24, 16), (255, 255, index % 255)).save(output, format="PNG")
    return output.getvalue()


def _data(response, expected: int = 200):
    assert response.status_code == expected, response.text
    return response.json()["data"]


def _upload(client: TestClient, headers: dict[str, str], kind: str, index: int = 0) -> dict:
    return _data(
        client.post(
            "/api/documents",
            headers={**headers, "Idempotency-Key": f"ocr-source-{kind}-{index}"},
            data={
                "document_type": kind,
                "external_processing_consent_version": "external-ocr-v1",
            },
            files={"file": (f"{kind}.png", _image(index), "image/png")},
        ),
        201,
    )


def _create(client: TestClient, headers: dict[str, str], document: dict) -> dict:
    return _data(
        client.post(
            "/api/ocr/tasks",
            headers=headers,
            json={
                "document_id": document["id"],
                "document_revision_id": document["current_revision_id"],
            },
        ),
        201,
    )


def _payload(kind: str) -> dict[str, Any]:
    drafts = {
        "lab_report": {"facility": " Pomi Hospital ", "report_date": None, "items": []},
        "medical_order": {"facility": None, "order_date": None, "medications": []},
        "imaging_text_report": {
            "facility": None,
            "report_date": None,
            "modality": "US",
            "findings": " visible text ",
            "impression": None,
        },
        "outpatient_record": {
            "facility": None,
            "department": None,
            "visit_date": None,
            "chief_complaint": None,
            "diagnoses": [],
            "plan": None,
        },
    }
    return {
        "draft": drafts[kind],
        "fields": [
            {
                "path": "facility",
                "source_text": " Pomi Hospital ",
                "value": drafts[kind].get("facility"),
                "confidence": 0.91,
                "uncertainty_reason": None,
                "source_region": {"page": 1, "x": 0.1, "y": 0.1, "width": 0.4, "height": 0.1},
            }
        ],
    }


class FakeProvider:
    def __init__(
        self, failures: list[OCRProviderError] | None = None, invalid: bool = False
    ) -> None:
        self.failures = list(failures or [])
        self.invalid = invalid
        self.requests: list[OCRProviderRequest] = []

    def recognize(self, request: OCRProviderRequest) -> OCRProviderResponse:
        self.requests.append(request)
        if self.failures:
            raise self.failures.pop(0)
        payload = {"unexpected": True} if self.invalid else _payload(request.material_type)
        return OCRProviderResponse(
            raw_response={"provider_request": len(self.requests), "payload": payload},
            payload=payload,
            source="fake-qwen3-vl",
        )


def _worker(client: TestClient, provider: FakeProvider) -> OCRWorker:
    return OCRWorker(
        client.app.state.session_factory,
        storage_root=client.app.state.settings.storage_root,
        provider=provider,
        worker_id="test-worker",
        lease_seconds=30,
    )


def _make_due(factory: sessionmaker[Session], task_id: str) -> None:
    with factory() as session:
        task = session.get(OCRTask, task_id)
        assert task is not None
        task.available_at = utc_now() - timedelta(seconds=1)
        session.commit()


def test_four_materials_are_idempotent_traceable_and_uid_scoped(api_client: TestClient) -> None:
    owner = _headers(api_client, "ocr-owner")
    outsider = _headers(api_client, "ocr-outsider")
    for index, kind in enumerate(
        ("lab_report", "medical_order", "imaging_text_report", "outpatient_record")
    ):
        document = _upload(api_client, owner, kind, index)
        task = _create(api_client, owner, document)
        repeated = _create(api_client, owner, document)
        assert repeated["id"] == task["id"]
        assert repeated["reused"] is True
        provider = FakeProvider()
        assert _worker(api_client, provider).run_once() is True
        assert len(provider.requests) == 1
        status = _data(api_client.get(f"/api/ocr/tasks/{task['id']}", headers=owner))
        assert status["status"] == "pending_confirmation"
        assert status["provider_attempts"] == 1
        result = _data(api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=owner))
        assert result["raw_response"]["provider_request"] == 1
        assert result["fields"][0]["confidence"] == 0.91
        assert result["fields"][0]["source_region"]["page"] == 1
        assert api_client.get(f"/api/ocr/tasks/{task['id']}", headers=outsider).status_code == 404
        assert (
            api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=outsider).status_code
            == 404
        )
        assert _worker(api_client, provider).run_once() is False
        assert len(provider.requests) == 1


def test_network_and_schema_retry_limits_and_manual_retry(api_client: TestClient) -> None:
    headers = _headers(api_client, "ocr-retries")
    document = _upload(api_client, headers, "lab_report")
    task = _create(api_client, headers, document)
    network = OCRProviderError(
        "network", "OCR_NETWORK_ERROR", "network unavailable", retryable=True
    )
    provider = FakeProvider(failures=[network, network, network])
    worker = _worker(api_client, provider)
    for expected_calls in (1, 2, 3):
        assert worker.run_once() is True
        if expected_calls < 3:
            _make_due(api_client.app.state.session_factory, task["id"])
    failed = _data(api_client.get(f"/api/ocr/tasks/{task['id']}", headers=headers))
    assert failed["status"] == "failed"
    assert failed["provider_attempts"] == 3
    assert len(provider.requests) == 3

    retried = _data(api_client.post(f"/api/ocr/tasks/{task['id']}/retry", headers=headers), 201)
    repeated = _data(api_client.post(f"/api/ocr/tasks/{task['id']}/retry", headers=headers), 201)
    assert retried["id"] == repeated["id"]
    assert retried["parent_task_id"] == task["id"]
    assert repeated["reused"] is True

    with api_client.app.state.session_factory() as session:
        retry_task = session.get(OCRTask, retried["id"])
        assert retry_task is not None
        retry_task.status = "failed"
        session.commit()

    second_document = _upload(api_client, headers, "medical_order", 2)
    schema_task = _create(api_client, headers, second_document)
    invalid_provider = FakeProvider(invalid=True)
    schema_worker = _worker(api_client, invalid_provider)
    assert schema_worker.run_once() is True
    _make_due(api_client.app.state.session_factory, schema_task["id"])
    assert schema_worker.run_once() is True
    invalid = _data(api_client.get(f"/api/ocr/tasks/{schema_task['id']}", headers=headers))
    assert invalid["status"] == "failed"
    assert invalid["provider_attempts"] == 2
    assert len(invalid_provider.requests) == 2


def test_lease_recovery_and_ambiguous_provider_call_are_not_replayed(
    api_client: TestClient,
) -> None:
    headers = _headers(api_client, "ocr-lease")
    first = _create(api_client, headers, _upload(api_client, headers, "outpatient_record", 1))
    second = _create(api_client, headers, _upload(api_client, headers, "outpatient_record", 2))
    with api_client.app.state.session_factory() as session:
        recoverable = session.get(OCRTask, first["id"])
        ambiguous = session.get(OCRTask, second["id"])
        assert recoverable is not None and ambiguous is not None
        for task in (recoverable, ambiguous):
            task.status = "processing"
            task.lease_owner = "dead-worker"
            task.lease_expires_at = utc_now() - timedelta(seconds=1)
        ambiguous.provider_call_started_at = utc_now() - timedelta(minutes=5)
        session.commit()
    provider = FakeProvider()
    worker = _worker(api_client, provider)
    assert worker.run_once() is True
    assert len(provider.requests) == 1
    recovered = _data(api_client.get(f"/api/ocr/tasks/{first['id']}", headers=headers))
    timed_out = _data(api_client.get(f"/api/ocr/tasks/{second['id']}", headers=headers))
    assert recovered["status"] == "pending_confirmation"
    assert timed_out["status"] == "timed_out"
    assert timed_out["error"]["code"] == "OCR_PROVIDER_OUTCOME_UNKNOWN"
    with api_client.app.state.session_factory() as session:
        assert session.query(OCRResult).count() == 1


def test_ocr_requires_consent_and_explicit_owned_revision(api_client: TestClient) -> None:
    headers = _headers(api_client, "ocr-consent")
    document = _data(
        api_client.post(
            "/api/documents",
            headers={**headers, "Idempotency-Key": "ocr-without-consent"},
            data={"document_type": "lab_report"},
            files={"file": ("lab.png", _image(), "image/png")},
        ),
        201,
    )
    response = api_client.post(
        "/api/ocr/tasks",
        headers=headers,
        json={
            "document_id": document["id"],
            "document_revision_id": document["current_revision_id"],
        },
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "EXTERNAL_PROCESSING_CONSENT_REQUIRED"

    schema = api_client.get("/openapi.json").json()
    assert set(schema["paths"]) >= {
        "/api/ocr/tasks",
        "/api/ocr/tasks/{task_id}",
        "/api/ocr/tasks/{task_id}/result",
        "/api/ocr/tasks/{task_id}/retry",
    }
