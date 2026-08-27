from __future__ import annotations

from io import BytesIO

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import text
from sqlalchemy.exc import DatabaseError

from pomi_backend.workers import run_ocr_once, run_pdf_once


def image_bytes() -> bytes:
    output = BytesIO()
    Image.new("RGB", (320, 240), color=(246, 241, 250)).save(output, format="PNG")
    return output.getvalue()


def auth_headers(client: TestClient) -> dict[str, str]:
    password = "ReportPass123"
    client.post(
        "/api/auth/register",
        json={"account_name": "report-user", "password": password},
    )
    login = client.post(
        "/api/auth/login",
        json={"account_name": "report-user", "password": password},
    )
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def data(response, status_code: int = 200):
    assert response.status_code == status_code, response.text
    return response.json()["data"]


def confirmed_medical_order(client: TestClient, headers: dict[str, str]) -> dict:
    document = data(
        client.post(
            "/api/documents",
            headers={**headers, "Idempotency-Key": "report-order-document"},
            data={"document_type": "medical_order"},
            files={"file": ("order.png", image_bytes(), "image/png")},
        ),
        201,
    )
    task = data(
        client.post(
            "/api/ocr/tasks",
            headers={**headers, "Idempotency-Key": "report-order-task"},
            json={
                "document_id": document["id"],
                "document_revision_id": document["current_revision_id"],
            },
        ),
        202,
    )
    assert run_ocr_once(client.app.state.session_factory, client.app.state.settings)
    draft = data(client.get(f"/api/ocr/tasks/{task['id']}/result", headers=headers))
    confirmations = [
        {
            "field_path": field["field_path"],
            "user_value": field["parsed_value"],
            "confirmation_status": "confirmed",
        }
        for field in draft["fields"]
    ]
    confirmed = data(
        client.post(
            f"/api/ocr/tasks/{task['id']}/confirm",
            headers={**headers, "Idempotency-Key": "report-order-confirm"},
            json={
                "result_id": draft["result_id"],
                "expected_revision_id": document["current_revision_id"],
                "document_type": "medical_order",
                "confirmed_data": draft["draft"],
                "field_confirmations": confirmations,
            },
        )
    )
    assert confirmed["reconciliation_required"] is True
    return document


def test_reconciliation_report_snapshot_and_pdf_flow(api_client: TestClient) -> None:
    headers = auth_headers(api_client)
    document = confirmed_medical_order(api_client, headers)
    reconciliation = data(
        api_client.post(
            "/api/medication-reconciliations",
            headers={**headers, "Idempotency-Key": "report-reconciliation"},
            json={"source_document_id": document["id"]},
        ),
        201,
    )
    assert reconciliation["status"] == "pending"
    assert reconciliation["items"][0]["comparison_type"] == "added"
    confirmed_reconciliation = data(
        api_client.put(
            f"/api/medication-reconciliations/{reconciliation['id']}",
            headers=headers,
            json={
                "status": "confirmed",
                "items": [
                    {
                        "item_id": item["id"],
                        "user_decision": "accept",
                    }
                    for item in reconciliation["items"]
                ],
            },
        )
    )
    assert confirmed_reconciliation["status"] == "confirmed"
    medications = data(api_client.get("/api/medications", headers=headers))
    assert medications["items"][0]["drug_name"] == "Metformin"

    note = data(
        api_client.post(
            "/api/patient-notes",
            headers=headers,
            json={
                "original_text": "I want to review my medicines.",
                "confirmed_text": "I want to review my medicines.",
                "confirmation_status": "confirmed",
            },
        ),
        201,
    )
    report = data(
        api_client.post(
            "/api/reports",
            headers={**headers, "Idempotency-Key": "report-snapshot-001"},
            json={"patient_note_id": note["id"]},
        ),
        201,
    )
    repeated = data(
        api_client.post(
            "/api/reports",
            headers={**headers, "Idempotency-Key": "report-snapshot-001"},
            json={"patient_note_id": note["id"]},
        ),
        201,
    )
    assert repeated["report_id"] == report["report_id"]
    detail = data(api_client.get(f"/api/reports/{report['report_id']}", headers=headers))
    assert detail["summary"]["patient_note_text"] == note["confirmed_text"]
    assert detail["sources"][0]["document_revision_id"] == document["current_revision_id"]

    with api_client.app.state.engine.connect() as connection:
        with pytest.raises(DatabaseError):
            connection.execute(
                text("UPDATE report_snapshot SET status='failed' WHERE id=:id"),
                {"id": report["report_id"]},
            )
            connection.commit()

    pdf = data(
        api_client.post(
            f"/api/reports/{report['report_id']}/pdf",
            headers={**headers, "Idempotency-Key": "report-pdf-001"},
        ),
        202,
    )
    assert pdf["generation_status"] == "pending"
    assert run_pdf_once(api_client.app.state.session_factory, api_client.app.state.settings)
    pdf = data(api_client.get(f"/api/reports/{report['report_id']}/pdf", headers=headers))
    assert pdf["generation_status"] == "succeeded"
    downloaded = api_client.get(f"/api/reports/{report['report_id']}/pdf/file", headers=headers)
    assert downloaded.status_code == 200
    assert downloaded.content.startswith(b"%PDF")


def test_unconfirmed_note_cannot_be_used_for_report(api_client: TestClient) -> None:
    headers = auth_headers_for_second_user(api_client)
    note = data(
        api_client.post(
            "/api/patient-notes",
            headers=headers,
            json={
                "original_text": "Draft note",
                "confirmation_status": "draft",
            },
        ),
        201,
    )
    response = api_client.post(
        "/api/reports",
        headers={**headers, "Idempotency-Key": "draft-report-001"},
        json={"patient_note_id": note["id"]},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "REPORT_SOURCE_INCOMPLETE"


def auth_headers_for_second_user(client: TestClient) -> dict[str, str]:
    password = "ReportSecond123"
    client.post(
        "/api/auth/register",
        json={"account_name": "report-second", "password": password},
    )
    login = client.post(
        "/api/auth/login",
        json={"account_name": "report-second", "password": password},
    )
    return {"Authorization": f"Bearer {login.json()['session_id']}"}
