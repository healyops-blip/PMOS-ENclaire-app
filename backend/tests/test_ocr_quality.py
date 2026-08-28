from __future__ import annotations

import hashlib
import io
import json
import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from pomi_backend.db.models import OCRFallbackUse, OCRTask
from pomi_backend.quality.ocr_evaluation import evaluate_ocr_quality
from pomi_backend.quality.ocr_observability import summarize_ocr_tasks
from pomi_backend.services.ocr_fallback import FALLBACK_DATA_VERSION
from pomi_backend.worker.ocr import OCRWorker
from pomi_backend.worker.ocr import logger as worker_logger

ROOT = Path(__file__).resolve().parents[1]
DATASET_ROOT = ROOT / "evaluation" / "ocr_quality"
ASSET_ROOT = ROOT.parent / "assets" / "demo"


def _headers(client: TestClient, account_name: str) -> dict[str, str]:
    password = "SyntheticQualityPass123"
    assert (
        client.post(
            "/api/auth/register", json={"account_name": account_name, "password": password}
        ).status_code
        == 201
    )
    login = client.post(
        "/api/auth/login", json={"account_name": account_name, "password": password}
    )
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def _task(client: TestClient, headers: dict[str, str], material_type: str, file: Path) -> dict:
    upload = client.post(
        "/api/documents",
        headers={**headers, "Idempotency-Key": f"quality-{material_type}-{file.stem}"},
        data={
            "document_type": material_type,
            "external_processing_consent_version": "external-ocr-v1",
        },
        files={"file": (file.name, file.read_bytes(), "image/png")},
    )
    assert upload.status_code == 201, upload.text
    document = upload.json()["data"]
    response = client.post(
        "/api/ocr/tasks",
        headers=headers,
        json={
            "document_id": document["id"],
            "document_revision_id": document["current_revision_id"],
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["data"]


def _fail(client: TestClient, task_id: str, category: str = "network") -> None:
    with client.app.state.session_factory() as session:
        task = session.get(OCRTask, task_id)
        assert task is not None
        task.status = "failed"
        task.error_category = category
        task.error_code = "OCR_NETWORK_ERROR" if category == "network" else "OCR_SCHEMA_INVALID"
        task.error_message = "safe synthetic failure"
        session.commit()


def test_dataset_has_ten_synthetic_hash_verified_samples_per_material() -> None:
    dataset = json.loads((DATASET_ROOT / "dataset.json").read_text(encoding="utf-8"))
    counts: dict[str, int] = {}
    for sample in dataset:
        counts[sample["material_type"]] = counts.get(sample["material_type"], 0) + 1
        path = DATASET_ROOT / sample["file"]
        assert path.is_file()
        assert hashlib.sha256(path.read_bytes()).hexdigest() == sample["sha256"]
        assert sample["synthetic"] is True
        assert sample["contains_real_patient_data"] is False
        assert {field["priority"] for field in sample["gold_fields"]} <= {"P0", "P1", "P2"}
        assert all(
            "allowed_values" in field and "error_note" in field for field in sample["gold_fields"]
        )
    assert counts == {
        "lab_report": 10,
        "medical_order": 10,
        "imaging_text_report": 10,
        "outpatient_record": 10,
    }


def test_evaluator_enforces_gates_and_excludes_fallback() -> None:
    dataset = json.loads((DATASET_ROOT / "dataset.json").read_text(encoding="utf-8"))
    predictions = json.loads(
        (DATASET_ROOT / "offline-perfect-predictions.json").read_text(encoding="utf-8")
    )
    fallback = {**predictions[0], "source": "fallback", "duration_ms": 999999}
    outcome = evaluate_ocr_quality(dataset, [*predictions, fallback])
    assert outcome.passed is True
    assert outcome.report["fallback_records_excluded"] == 1
    assert outcome.report["latency_ms"]["p95"] < 999999
    broken = json.loads(json.dumps(predictions))
    broken[0]["payload"]["draft"]["items"][0]["numeric_value"] = 999
    failed = evaluate_ocr_quality(dataset, broken)
    assert failed.passed is False
    assert failed.report["critical_failure_count"] == 1

    mostly_failed = json.loads(json.dumps(predictions))
    for record in mostly_failed[1:]:
        record["status"] = "failed"
        record.pop("payload")
        record["error_category"] = "provider_unavailable"
    sparse = evaluate_ocr_quality(dataset, mostly_failed)
    assert sparse.passed is False
    assert sparse.report["schema_pass_rate"] == 0.025
    assert sparse.report["field_accuracy"]["P0"] < 0.95


def test_operational_metrics_exclude_fallback_and_never_emit_medical_values() -> None:
    now = datetime.now(UTC)
    tasks = [
        SimpleNamespace(
            status="confirmed",
            result_source="qwen3-vl",
            duration_ms=800,
            error_category=None,
            lease_expires_at=None,
        ),
        SimpleNamespace(
            status="confirmed",
            result_source="fallback",
            duration_ms=999999,
            error_category=None,
            lease_expires_at=None,
        ),
        SimpleNamespace(
            status="processing",
            result_source=None,
            duration_ms=None,
            error_category="network",
            lease_expires_at=now - timedelta(seconds=1),
        ),
    ]
    report = summarize_ocr_tasks(tasks, now=now)
    assert report["fallback_count_excluded"] == 1
    assert report["real_model_latency_ms"] == {"sample_count": 1, "p50": 800, "p95": 800}
    assert report["lease_anomalies"] == 1
    serialized = json.dumps(report)
    assert "patient" not in serialized
    assert "raw_response" not in serialized


def test_worker_log_contains_only_safe_operational_identifiers() -> None:
    worker = OCRWorker(  # type: ignore[arg-type]
        None,
        storage_root=Path("."),
        provider=None,  # type: ignore[arg-type]
        worker_id="privacy-test",
    )
    task = SimpleNamespace(
        requested_by_uid="private-user-id",
        id="safe-task-id",
        document_id="safe-document-id",
        error_category="network",
        duration_ms=123,
        error_message="DO-NOT-LOG medical full text Authorization Session password",
    )
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    previous_level = worker_logger.level
    previous_disabled = worker_logger.disabled
    worker_logger.addHandler(handler)
    worker_logger.setLevel(logging.INFO)
    worker_logger.disabled = False
    try:
        worker._log(task, "failed")
    finally:
        worker_logger.removeHandler(handler)
        worker_logger.setLevel(previous_level)
        worker_logger.disabled = previous_disabled
    output = stream.getvalue()
    assert "safe-task-id" in output
    assert "medical full text" not in output
    assert "Authorization" not in output
    assert "Session" not in output
    assert "password" not in output
    assert "private-user-id" not in output


def test_exact_demo_fallback_requires_failure_match_version_and_consent(
    api_client: TestClient,
) -> None:
    owner = _headers(api_client, "quality-owner")
    outsider = _headers(api_client, "quality-outsider")
    task = _task(api_client, owner, "lab_report", ASSET_ROOT / "lab_report.png")
    _fail(api_client, task["id"])

    eligibility = api_client.get(f"/api/ocr/tasks/{task['id']}/fallback", headers=owner)
    assert eligibility.status_code == 200
    assert eligibility.json()["data"] == {
        "eligible": True,
        "data_version": FALLBACK_DATA_VERSION,
        "reason": "exact_match",
    }
    assert (
        api_client.get(f"/api/ocr/tasks/{task['id']}/fallback", headers=outsider).status_code == 404
    )

    declined = api_client.post(
        f"/api/ocr/tasks/{task['id']}/fallback",
        headers=owner,
        json={"accept": False, "data_version": FALLBACK_DATA_VERSION},
    )
    assert declined.json()["data"]["status"] == "failed"
    accepted = api_client.post(
        f"/api/ocr/tasks/{task['id']}/fallback",
        headers=owner,
        json={"accept": True, "data_version": FALLBACK_DATA_VERSION},
    )
    assert accepted.status_code == 200, accepted.text
    data = accepted.json()["data"]
    assert data["status"] == "pending_confirmation"
    assert data["result_source"] == "fallback"
    assert data["fallback"]["data_version"] == FALLBACK_DATA_VERSION
    assert data["fallback"]["trigger_reason"]["category"] == "network"
    document = api_client.get(f"/api/documents/{task['document_id']}", headers=owner).json()["data"]
    assert document["latest_ocr_result_source"] == "fallback"
    assert document["latest_ocr_fallback_version"] == FALLBACK_DATA_VERSION
    result = api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=owner).json()["data"]
    assert result["result_source"] == "fallback"
    assert result["validated_draft"]["items"][0]["item_name"] == "LH"
    repeated = api_client.post(
        f"/api/ocr/tasks/{task['id']}/fallback",
        headers=owner,
        json={"accept": True, "data_version": FALLBACK_DATA_VERSION},
    )
    assert repeated.json()["data"]["reused"] is True
    confirmed = api_client.post(
        f"/api/ocr/tasks/{task['id']}/confirm",
        headers=owner,
        json={
            "result_id": result["id"],
            "expected_revision_id": task["document_revision_id"],
            "report_date": "2026-07-01",
            "items": [
                {
                    "name": "LH",
                    "value": "4.1",
                    "unit": "IU/L",
                    "reference_range": None,
                    "report_date": "2026-07-01",
                }
            ],
        },
    )
    assert confirmed.status_code == 200, confirmed.text
    with api_client.app.state.session_factory() as session:
        audit = session.query(OCRFallbackUse).one()
        assert audit.confirmed_by_uid == audit.selected_by_uid
        assert audit.confirmed_at is not None


def test_unregistered_type_hash_and_ineligible_error_never_receive_fallback(
    api_client: TestClient,
) -> None:
    headers = _headers(api_client, "quality-negative")
    mismatched = _task(api_client, headers, "medical_order", ASSET_ROOT / "lab_report.png")
    _fail(api_client, mismatched["id"])
    data = api_client.get(f"/api/ocr/tasks/{mismatched['id']}/fallback", headers=headers).json()[
        "data"
    ]
    assert data == {"eligible": False, "data_version": None, "reason": "file_not_registered"}
    denied = api_client.post(
        f"/api/ocr/tasks/{mismatched['id']}/fallback",
        headers=headers,
        json={"accept": True, "data_version": FALLBACK_DATA_VERSION},
    )
    assert denied.status_code == 409
    assert denied.json()["error"]["code"] == "OCR_FALLBACK_NOT_AVAILABLE"

    schema_failed = _task(
        api_client, headers, "imaging_text_report", ASSET_ROOT / "imaging_text_report.png"
    )
    _fail(api_client, schema_failed["id"], "response_format")
    unavailable = api_client.get(
        f"/api/ocr/tasks/{schema_failed['id']}/fallback", headers=headers
    ).json()["data"]
    assert unavailable["eligible"] is False
    assert unavailable["reason"] == "failure_not_eligible"

    wrong_version = _task(
        api_client, headers, "outpatient_record", ASSET_ROOT / "outpatient_record.png"
    )
    _fail(api_client, wrong_version["id"])
    response = api_client.post(
        f"/api/ocr/tasks/{wrong_version['id']}/fallback",
        headers=headers,
        json={"accept": True, "data_version": "unregistered-version"},
    )
    assert response.status_code == 409


def test_deleted_document_cannot_receive_a_fallback(api_client: TestClient) -> None:
    headers = _headers(api_client, "quality-deleted")
    task = _task(api_client, headers, "lab_report", ASSET_ROOT / "lab_report.png")
    assert (
        api_client.delete(f"/api/documents/{task['document_id']}", headers=headers).status_code
        == 200
    )
    _fail(api_client, task["id"])

    eligibility = api_client.get(f"/api/ocr/tasks/{task['id']}/fallback", headers=headers).json()[
        "data"
    ]
    assert eligibility == {
        "eligible": False,
        "data_version": None,
        "reason": "document_not_available",
    }
    denied = api_client.post(
        f"/api/ocr/tasks/{task['id']}/fallback",
        headers=headers,
        json={"accept": True, "data_version": FALLBACK_DATA_VERSION},
    )
    assert denied.status_code == 409


def test_concurrent_fallback_acceptance_creates_one_result_and_audit(
    api_client: TestClient,
) -> None:
    headers = _headers(api_client, "quality-concurrent")
    task = _task(api_client, headers, "lab_report", ASSET_ROOT / "lab_report.png")
    _fail(api_client, task["id"])

    def accept() -> tuple[int, dict]:
        response = api_client.post(
            f"/api/ocr/tasks/{task['id']}/fallback",
            headers=headers,
            json={"accept": True, "data_version": FALLBACK_DATA_VERSION},
        )
        return response.status_code, response.json()

    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(executor.map(lambda _: accept(), range(2)))

    assert [status for status, _ in responses] == [200, 200]
    assert sorted(body["data"]["reused"] for _, body in responses) == [False, True]
    with api_client.app.state.session_factory() as session:
        assert session.query(OCRFallbackUse).count() == 1


def test_all_four_registered_demo_materials_enter_the_shared_confirmation_flow(
    api_client: TestClient,
) -> None:
    headers = _headers(api_client, "quality-four-types")
    cases = {
        "lab_report": "lab_report.png",
        "medical_order": "medical_order.png",
        "imaging_text_report": "imaging_text_report.png",
        "outpatient_record": "outpatient_record.png",
    }
    for material_type, file_name in cases.items():
        task = _task(api_client, headers, material_type, ASSET_ROOT / file_name)
        _fail(api_client, task["id"])
        response = api_client.post(
            f"/api/ocr/tasks/{task['id']}/fallback",
            headers=headers,
            json={"accept": True, "data_version": FALLBACK_DATA_VERSION},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["status"] == "pending_confirmation"
        result = api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=headers).json()[
            "data"
        ]
        assert result["result_source"] == "fallback"
        assert result["validated_draft"]
