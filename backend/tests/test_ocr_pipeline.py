from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from io import BytesIO
from typing import Any

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy.orm import Session, sessionmaker

from pomi_backend.config import Settings
from pomi_backend.db.models import (
    Document,
    ImagingReport,
    Medication,
    OCRFieldResult,
    OCRResult,
    OCRTask,
    OutpatientRecord,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.repositories import OCRRepository
from pomi_backend.services.ocr_provider import (
    OCRProviderError,
    OCRProviderRequest,
    OCRProviderResponse,
)
from pomi_backend.worker.ocr import OCRWorker, build_worker


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


def _clinical_confirmation(kind: str, result: dict, document: dict) -> dict[str, Any]:
    confirmed_data = (
        {
            "examination_name": "Pelvic ultrasound",
            "body_part": "Pelvis",
            "examination_method": "US",
            "examined_at": "2026-08-20",
            "reported_at": "2026-08-21",
            "findings_text": "Verbatim imaging findings.",
            "conclusion_text": "Verbatim imaging conclusion.",
        }
        if kind == "imaging_text_report"
        else {
            "hospital_name": "Synthetic Hospital",
            "department_name": "Endocrinology",
            "doctor_name": None,
            "visit_date": "2026-08-20",
            "chief_complaint": "Irregular cycles.",
            "diagnosis_summary": "Verbatim diagnosis summary.",
            "treatment_plan": "Medication words remain text only.",
            "medical_advice": "Verbatim follow-up advice.",
        }
    )
    return {
        "result_id": result["id"],
        "expected_revision_id": document["current_revision_id"],
        "document_type": kind,
        "confirmed_data": confirmed_data,
        "field_confirmations": [],
    }


def _payload(kind: str) -> dict[str, Any]:
    drafts = {
        "lab_report": {
            "hospital_name": " Pomi Hospital ",
            "sample_date": None,
            "report_date": None,
            "items": [
                {
                    "item_name": "Glucose",
                    "item_code": None,
                    "raw_value": "5.2",
                    "numeric_value": 5.2,
                    "raw_unit": "mmol/L",
                    "normalized_unit": "mmol/L",
                    "reference_range_text": "3.9-6.1",
                    "reference_low": 3.9,
                    "reference_high": 6.1,
                }
            ],
        },
        "medical_order": {
            "hospital_name": None,
            "department_name": None,
            "prescribed_at": None,
            "orders": [
                {
                    "source_text": "Metformin 500 mg twice daily",
                    "drug_name": "Metformin",
                    "normalized_drug_name": "metformin",
                    "specification": "500 mg",
                    "dosage_text": "500 mg",
                    "dosage_value": 500,
                    "dosage_unit": "mg",
                    "frequency": "twice daily",
                    "duration": None,
                    "route": "oral",
                    "instruction": None,
                }
            ],
        },
        "imaging_text_report": {
            "examination_name": "US",
            "body_part": None,
            "examination_method": None,
            "findings_text": " visible text ",
            "conclusion_text": None,
            "examined_at": None,
            "reported_at": None,
        },
        "outpatient_record": {
            "hospital_name": None,
            "department_name": None,
            "doctor_name": None,
            "visit_date": None,
            "chief_complaint": None,
            "diagnosis_summary": None,
            "treatment_plan": None,
            "medical_advice": None,
        },
    }
    draft = drafts[kind]
    return {
        "draft": draft,
        "fields": _field_evidence(draft),
    }


def _field_evidence(value: Any, path: str = "") -> list[dict[str, Any]]:
    if isinstance(value, dict):
        return [
            field
            for key, child in value.items()
            for field in _field_evidence(child, f"{path}.{key}" if path else key)
        ]
    if isinstance(value, list):
        return [
            field
            for index, child in enumerate(value)
            for field in _field_evidence(child, f"{path}[{index}]")
        ]
    return [
        {
            "path": path,
            "source_text": value if isinstance(value, str) else None,
            "value": value,
            "confidence": 0.91,
            "uncertainty_reason": None,
            "source_region": {"page": 1, "x": 0.1, "y": 0.1, "width": 0.4, "height": 0.1},
        }
    ]


class FakeProvider:
    def __init__(
        self,
        failures: list[OCRProviderError] | None = None,
        invalid: bool = False,
        invalid_evidence: bool = False,
        invalid_date: bool = False,
    ) -> None:
        self.failures = list(failures or [])
        self.invalid = invalid
        self.invalid_evidence = invalid_evidence
        self.invalid_date = invalid_date
        self.requests: list[OCRProviderRequest] = []

    def recognize(self, request: OCRProviderRequest) -> OCRProviderResponse:
        self.requests.append(request)
        if self.failures:
            raise self.failures.pop(0)
        payload = {"unexpected": True} if self.invalid else _payload(request.material_type)
        if self.invalid_evidence:
            payload["fields"][0]["path"] = "invented.patient.field"
        if self.invalid_date:
            payload["draft"]["report_date"] = "2026-99-99"
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
        assert result["source_document"]["document_revision_id"] == document["current_revision_id"]
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
    first_started_at = None
    for expected_calls in (1, 2, 3):
        assert worker.run_once() is True
        with api_client.app.state.session_factory() as session:
            stored_task = session.get(OCRTask, task["id"])
            assert stored_task is not None
            first_started_at = first_started_at or stored_task.started_at
            assert stored_task.started_at == first_started_at
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

    evidence_document = _upload(api_client, headers, "imaging_text_report", 3)
    evidence_task = _create(api_client, headers, evidence_document)
    evidence_provider = FakeProvider(invalid_evidence=True)
    assert _worker(api_client, evidence_provider).run_once() is True
    evidence = _data(api_client.get(f"/api/ocr/tasks/{evidence_task['id']}", headers=headers))
    assert evidence["status"] == "queued"
    assert evidence["error"]["code"] == "OCR_SCHEMA_INVALID"
    with api_client.app.state.session_factory() as session:
        assert (
            session.query(OCRResult).filter(OCRResult.task_id == evidence_task["id"]).count() == 0
        )


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
    assert timed_out["attempt_history"][-1]["status"] == "timed_out"
    assert timed_out["duration_ms"] is not None
    with api_client.app.state.session_factory() as session:
        assert session.query(OCRResult).count() == 1


def test_stale_provider_response_cannot_overwrite_expired_lease(api_client: TestClient) -> None:
    headers = _headers(api_client, "ocr-stale-response")
    task = _create(api_client, headers, _upload(api_client, headers, "lab_report"))
    failed_task = _create(
        api_client,
        headers,
        _upload(api_client, headers, "medical_order", 1),
    )
    factory = api_client.app.state.session_factory

    class ExpiringProvider(FakeProvider):
        def __init__(self, *, fail_after_expiry: bool = False) -> None:
            super().__init__()
            self.fail_after_expiry = fail_after_expiry

        def recognize(self, request: OCRProviderRequest) -> OCRProviderResponse:
            with factory() as other_session:
                active = other_session.get(OCRTask, request.task_id)
                assert active is not None
                active.lease_expires_at = utc_now() - timedelta(seconds=1)
                other_session.commit()
                assert OCRRepository(other_session).expire_ambiguous_calls(now=utc_now()) == 1
            if self.fail_after_expiry:
                raise OCRProviderError(
                    "network",
                    "OCR_NETWORK_ERROR",
                    "late provider failure",
                    retryable=True,
                )
            return super().recognize(request)

    assert _worker(api_client, ExpiringProvider()).run_once() is True
    assert _worker(api_client, ExpiringProvider(fail_after_expiry=True)).run_once() is True
    stored = _data(api_client.get(f"/api/ocr/tasks/{task['id']}", headers=headers))
    failed_stored = _data(api_client.get(f"/api/ocr/tasks/{failed_task['id']}", headers=headers))
    assert stored["status"] == "timed_out"
    assert stored["error"]["code"] == "OCR_PROVIDER_OUTCOME_UNKNOWN"
    assert failed_stored["status"] == "timed_out"
    assert failed_stored["error"]["code"] == "OCR_PROVIDER_OUTCOME_UNKNOWN"
    with factory() as session:
        assert (
            session.query(OCRResult)
            .filter(OCRResult.task_id.in_([task["id"], failed_task["id"]]))
            .count()
            == 0
        )

    date_document = _upload(api_client, headers, "lab_report", 4)
    date_task = _create(api_client, headers, date_document)
    date_provider = FakeProvider(invalid_date=True)
    assert _worker(api_client, date_provider).run_once() is True
    invalid_date = _data(api_client.get(f"/api/ocr/tasks/{date_task['id']}", headers=headers))
    assert invalid_date["status"] == "queued"
    assert invalid_date["error"]["code"] == "OCR_SCHEMA_INVALID"


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


def test_imaging_and_outpatient_confirmation_is_idempotent_and_traceable(
    api_client: TestClient,
) -> None:
    owner = _headers(api_client, "clinical-owner")
    outsider = _headers(api_client, "clinical-outsider")
    cases = {
        "imaging_text_report": {
            "examination_name": "Pelvic ultrasound",
            "body_part": "Pelvis",
            "examination_method": "US",
            "examined_at": "2026-08-20",
            "reported_at": "2026-08-21",
            "findings_text": "Verbatim imaging findings.",
            "conclusion_text": "Verbatim imaging conclusion.",
        },
        "outpatient_record": {
            "hospital_name": "Synthetic Hospital",
            "department_name": "Endocrinology",
            "doctor_name": None,
            "visit_date": "2026-08-20",
            "chief_complaint": "Irregular cycles.",
            "diagnosis_summary": "Verbatim diagnosis summary.",
            "treatment_plan": "Medication words remain text only.",
            "medical_advice": "Verbatim follow-up advice.",
        },
    }
    record_ids = []
    for index, (kind, confirmed_data) in enumerate(cases.items()):
        document = _upload(api_client, owner, kind, index + 20)
        task = _create(api_client, owner, document)
        assert _worker(api_client, FakeProvider()).run_once() is True
        result = _data(api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=owner))
        payload = {
            "result_id": result["id"],
            "expected_revision_id": document["current_revision_id"],
            "document_type": kind,
            "confirmed_data": confirmed_data,
            "field_confirmations": [
                {
                    "field_path": next(iter(confirmed_data)),
                    "user_value": confirmed_data[next(iter(confirmed_data))],
                    "confirmation_status": "edited",
                }
            ],
        }
        confirmed = _data(
            api_client.post(
                f"/api/ocr/tasks/{task['id']}/confirm",
                headers={**owner, "Idempotency-Key": f"clinical-confirm-{index}"},
                json=payload,
            )
        )
        repeated = _data(
            api_client.post(
                f"/api/ocr/tasks/{task['id']}/confirm",
                headers={**owner, "Idempotency-Key": f"clinical-confirm-{index}"},
                json=payload,
            )
        )
        assert repeated["record_id"] == confirmed["record_id"]
        assert repeated["reused"] is True
        assert confirmed["document_id"] == document["id"]
        assert confirmed["document_revision_id"] == document["current_revision_id"]
        assert (
            confirmed["p0_evaluation"]["valid_required_fields"]
            == confirmed["p0_evaluation"]["required_fields"]
        )
        changed_key = "medical_advice" if kind == "outpatient_record" else "conclusion_text"
        changed_payload = {
            **payload,
            "confirmed_data": {**confirmed_data, changed_key: "Different replay content."},
        }
        conflict = api_client.post(
            f"/api/ocr/tasks/{task['id']}/confirm", headers=owner, json=changed_payload
        )
        assert conflict.status_code == 409
        assert conflict.json()["error"]["code"] == "OCR_ALREADY_CONFIRMED"
        record_ids.append(confirmed["record_id"])
        assert (
            api_client.post(
                f"/api/ocr/tasks/{task['id']}/confirm",
                headers={**outsider, "Idempotency-Key": f"clinical-outsider-{index}"},
                json=payload,
            ).status_code
            == 404
        )

    with api_client.app.state.session_factory() as session:
        assert session.query(ImagingReport).count() == 1
        assert session.query(OutpatientRecord).count() == 1
        assert session.query(Medication).count() == 0
        assert {field.confirmation_status for field in session.query(OCRFieldResult).all()} <= {
            "confirmed",
            "edited",
            "rejected",
            None,
        }


def test_clinical_confirmation_rejects_blank_text_and_future_date(
    api_client: TestClient,
) -> None:
    headers = _headers(api_client, "clinical-invalid")
    document = _upload(api_client, headers, "outpatient_record", 41)
    task = _create(api_client, headers, document)
    assert _worker(api_client, FakeProvider()).run_once() is True
    result = _data(api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=headers))
    response = api_client.post(
        f"/api/ocr/tasks/{task['id']}/confirm",
        headers={**headers, "Idempotency-Key": "clinical-invalid-confirm"},
        json={
            "result_id": result["id"],
            "expected_revision_id": document["current_revision_id"],
            "document_type": "outpatient_record",
            "confirmed_data": {
                "hospital_name": None,
                "department_name": None,
                "doctor_name": None,
                "visit_date": "2099-01-01",
                "chief_complaint": None,
                "diagnosis_summary": " ",
                "treatment_plan": None,
                "medical_advice": " ",
            },
            "field_confirmations": [],
        },
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] in {
        "OCR_CONFIRMATION_INVALID",
        "OCR_CONFIRMATION_INVALID_DATE",
    }
    assert {item["path"] for item in response.json()["error"]["details"]["fields"]} & {
        "visit_date",
        "diagnosis_summary",
        "medical_advice",
    }
    with api_client.app.state.session_factory() as session:
        assert session.query(OutpatientRecord).count() == 0


def test_concurrent_identical_clinical_confirmation_creates_one_record(
    api_client: TestClient,
) -> None:
    headers = _headers(api_client, "clinical-concurrent")
    document = _upload(api_client, headers, "imaging_text_report", 42)
    task = _create(api_client, headers, document)
    assert _worker(api_client, FakeProvider()).run_once() is True
    result = _data(api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=headers))
    payload = _clinical_confirmation("imaging_text_report", result, document)

    def confirm() -> tuple[int, dict]:
        response = api_client.post(
            f"/api/ocr/tasks/{task['id']}/confirm", headers=headers, json=payload
        )
        return response.status_code, response.json()

    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(executor.map(lambda _: confirm(), range(2)))

    assert {status for status, _ in responses} == {200}
    data = [body["data"] for _, body in responses]
    assert {item["reused"] for item in data} == {False, True}
    assert data[0]["record_id"] == data[1]["record_id"]
    with api_client.app.state.session_factory() as session:
        assert session.query(ImagingReport).count() == 1


def test_deleted_clinical_source_and_revoked_session_cannot_confirm(
    api_client: TestClient,
) -> None:
    headers = _headers(api_client, "clinical-deleted")
    document = _upload(api_client, headers, "outpatient_record", 43)
    task = _create(api_client, headers, document)
    assert _worker(api_client, FakeProvider()).run_once() is True
    result = _data(api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=headers))
    payload = _clinical_confirmation("outpatient_record", result, document)

    assert api_client.delete(f"/api/documents/{document['id']}", headers=headers).status_code == 200
    response = api_client.post(
        f"/api/ocr/tasks/{task['id']}/confirm", headers=headers, json=payload
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "RESOURCE_NOT_FOUND"
    assert api_client.post("/api/auth/logout", headers=headers).status_code == 204
    assert (
        api_client.post(
            f"/api/ocr/tasks/{task['id']}/confirm", headers=headers, json=payload
        ).status_code
        == 401
    )
    with api_client.app.state.session_factory() as session:
        assert session.query(OutpatientRecord).count() == 0


def test_ocr_requires_a_live_authenticated_session(api_client: TestClient) -> None:
    headers = _headers(api_client, "ocr-revoked-session")
    document = _upload(api_client, headers, "medical_order")
    task = _create(api_client, headers, document)

    assert api_client.get(f"/api/ocr/tasks/{task['id']}").status_code == 401
    assert api_client.post("/api/auth/logout", headers=headers).status_code == 204
    assert api_client.get(f"/api/ocr/tasks/{task['id']}", headers=headers).status_code == 401
    assert api_client.post(f"/api/ocr/tasks/{task['id']}/retry", headers=headers).status_code == 401


def test_deleted_document_is_never_sent_to_the_provider(api_client: TestClient) -> None:
    headers = _headers(api_client, "ocr-deleted-document")
    document = _upload(api_client, headers, "outpatient_record")
    task = _create(api_client, headers, document)
    assert api_client.delete(f"/api/documents/{document['id']}", headers=headers).status_code == 200
    provider = FakeProvider()

    assert _worker(api_client, provider).run_once() is True
    assert provider.requests == []
    failed = _data(api_client.get(f"/api/ocr/tasks/{task['id']}", headers=headers))
    assert failed["status"] == "failed"
    assert failed["error"]["code"] == "OCR_FILE_NOT_FOUND"
    assert api_client.post(f"/api/ocr/tasks/{task['id']}/retry", headers=headers).status_code == 404


def test_document_deleted_during_provider_call_discards_the_result(api_client: TestClient) -> None:
    headers = _headers(api_client, "ocr-delete-in-flight")
    document = _upload(api_client, headers, "lab_report")
    task = _create(api_client, headers, document)
    factory = api_client.app.state.session_factory

    class DeletingProvider(FakeProvider):
        def recognize(self, request: OCRProviderRequest) -> OCRProviderResponse:
            with factory() as other_session:
                stored = other_session.get(Document, document["id"])
                assert stored is not None
                stored.deleted_at = utc_now()
                stored.upload_status = "deleted"
                other_session.commit()
            return super().recognize(request)

    assert _worker(api_client, DeletingProvider()).run_once() is True
    with factory() as session:
        assert session.query(OCRResult).filter(OCRResult.task_id == task["id"]).count() == 0
        assert (
            OCRRepository(session).expire_ambiguous_calls(now=utc_now() + timedelta(seconds=31))
            == 1
        )
    timed_out = _data(api_client.get(f"/api/ocr/tasks/{task['id']}", headers=headers))
    assert timed_out["status"] == "timed_out"


def test_worker_rejects_a_lease_shorter_than_provider_timeout(tmp_path) -> None:
    settings = Settings(
        database_url=f"sqlite:///{tmp_path / 'unsafe-worker.db'}",
        storage_root=tmp_path / "storage",
        ocr_request_timeout_seconds=90,
        ocr_lease_seconds=119,
    )
    with pytest.raises(ValueError, match="timeout \\+ 30"):
        build_worker(settings)

    with pytest.raises(ValueError, match="POMI_OCR_API_KEY"):
        build_worker(
            Settings(
                database_url=f"sqlite:///{tmp_path / 'unconfigured-worker.db'}",
                storage_root=tmp_path / "storage",
            )
        )
