from __future__ import annotations

from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import func, select

from pomi_backend.db.models import LabObservation
from pomi_backend.workers import run_ocr_once


def image_bytes() -> bytes:
    output = BytesIO()
    Image.new("RGB", (320, 240), color=(247, 242, 252)).save(output, format="PNG")
    return output.getvalue()


def auth_headers(client: TestClient) -> dict[str, str]:
    password = "OcrPass123"
    assert (
        client.post(
            "/api/auth/register",
            json={"account_name": "ocr-user", "password": password},
        ).status_code
        == 201
    )
    login = client.post(
        "/api/auth/login",
        json={"account_name": "ocr-user", "password": password},
    )
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def data(response, status_code: int = 200):
    assert response.status_code == status_code, response.text
    return response.json()["data"]


def test_mock_ocr_draft_validation_and_confirmation(api_client: TestClient) -> None:
    headers = auth_headers(api_client)
    upload_headers = {**headers, "Idempotency-Key": "ocr-document-001"}
    document = data(
        api_client.post(
            "/api/documents",
            headers=upload_headers,
            data={"document_type": "lab_report"},
            files={"file": ("lab.png", image_bytes(), "image/png")},
        ),
        201,
    )
    task = data(
        api_client.post(
            "/api/ocr/tasks",
            headers={**headers, "Idempotency-Key": "ocr-task-001"},
            json={
                "document_id": document["id"],
                "document_revision_id": document["current_revision_id"],
            },
        ),
        202,
    )
    assert task["task_status"] == "pending"
    not_ready = api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=headers)
    assert not_ready.status_code == 409
    assert not_ready.json()["error"]["code"] == "OCR_RESULT_NOT_READY"

    assert (
        run_ocr_once(
            api_client.app.state.session_factory,
            api_client.app.state.settings,
        )
        is True
    )
    finished = data(api_client.get(f"/api/ocr/tasks/{task['id']}", headers=headers))
    assert finished["task_status"] == "fallback"
    draft = data(api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=headers))
    assert draft["result_source"] == "fallback"
    assert draft["draft"]["items"][0]["raw_value"] == "1.42"
    assert draft["fields"]

    invalid = dict(draft["draft"])
    invalid["items"] = [{}]
    invalid_response = api_client.post(
        f"/api/ocr/tasks/{task['id']}/confirm",
        headers={**headers, "Idempotency-Key": "ocr-confirm-invalid"},
        json={
            "result_id": draft["result_id"],
            "expected_revision_id": document["current_revision_id"],
            "document_type": "lab_report",
            "confirmed_data": invalid,
            "field_confirmations": [],
            "confirm_all": True,
        },
    )
    assert invalid_response.status_code == 422
    assert invalid_response.json()["error"]["code"] == "SCHEMA_VALIDATION_FAILED"

    confirmed = data(
        api_client.post(
            f"/api/ocr/tasks/{task['id']}/confirm",
            headers={**headers, "Idempotency-Key": "ocr-confirm-001"},
            json={
                "result_id": draft["result_id"],
                "expected_revision_id": document["current_revision_id"],
                "document_type": "lab_report",
                "confirmed_data": draft["draft"],
                "field_confirmations": [],
                "confirm_all": True,
            },
        )
    )
    assert len(confirmed["created_resource_ids"]) == 1
    assert confirmed["reconciliation_required"] is False

    with api_client.app.state.session_factory() as session:
        assert session.scalar(select(func.count()).select_from(LabObservation)) == 1

    duplicate = data(
        api_client.post(
            f"/api/ocr/tasks/{task['id']}/confirm",
            headers={**headers, "Idempotency-Key": "ocr-confirm-001"},
            json={
                "result_id": draft["result_id"],
                "expected_revision_id": document["current_revision_id"],
                "document_type": "lab_report",
                "confirmed_data": draft["draft"],
                "field_confirmations": [],
                "confirm_all": True,
            },
        )
    )
    assert duplicate == confirmed


def test_ocr_task_is_idempotent(api_client: TestClient) -> None:
    headers = auth_headers_for_second_user(api_client)
    document = data(
        api_client.post(
            "/api/documents",
            headers={**headers, "Idempotency-Key": "ocr-document-002"},
            data={"document_type": "imaging_text_report"},
            files={"file": ("imaging.png", image_bytes(), "image/png")},
        ),
        201,
    )
    request = {
        "document_id": document["id"],
        "document_revision_id": document["current_revision_id"],
    }
    task_headers = {**headers, "Idempotency-Key": "ocr-task-002"}
    first = data(api_client.post("/api/ocr/tasks", headers=task_headers, json=request), 202)
    second = data(api_client.post("/api/ocr/tasks", headers=task_headers, json=request), 202)
    assert first["id"] == second["id"]


def auth_headers_for_second_user(client: TestClient) -> dict[str, str]:
    password = "OcrSecond123"
    client.post(
        "/api/auth/register",
        json={"account_name": "ocr-second", "password": password},
    )
    login = client.post(
        "/api/auth/login",
        json={"account_name": "ocr-second", "password": password},
    )
    return {"Authorization": f"Bearer {login.json()['session_id']}"}
