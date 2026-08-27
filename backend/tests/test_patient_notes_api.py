from __future__ import annotations

from fastapi.testclient import TestClient


def auth_headers(client: TestClient, account_name: str) -> dict[str, str]:
    password = "dddddddd4"
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


def value(response, status_code: int = 200):
    assert response.status_code == status_code, response.text
    return response.json()["data"]


def test_patient_note_draft_confirm_edit_reconfirm_skip_and_copy(api_client: TestClient) -> None:
    headers = auth_headers(api_client, "note-owner")
    note = value(
        api_client.post(
            "/api/patient-notes",
            headers=headers,
            json={"original_text": "I want to discuss fatigue.", "visit_context": "next visit"},
        ),
        201,
    )
    assert note["status"] == "draft"
    assert value(api_client.get("/api/patient-notes/latest", headers=headers))["id"] == note["id"]

    confirmed = value(api_client.post(f"/api/patient-notes/{note['id']}/confirm", headers=headers))
    repeated = value(api_client.post(f"/api/patient-notes/{note['id']}/confirm", headers=headers))
    assert confirmed["status"] == "confirmed"
    assert repeated["confirmed_at"] == confirmed["confirmed_at"]
    assert confirmed["confirmed_text"] == "I want to discuss fatigue."

    edited = value(
        api_client.put(
            f"/api/patient-notes/{note['id']}",
            headers=headers,
            json={"original_text": "Discuss fatigue and sleep.", "visit_context": "next visit"},
        )
    )
    assert edited["status"] == "draft"
    assert edited["confirmed_text"] is None
    confirmed = value(api_client.post(f"/api/patient-notes/{note['id']}/confirm", headers=headers))

    copied = value(
        api_client.post(
            f"/api/patient-notes/{note['id']}/copy",
            headers=headers,
            json={"visit_context": "following visit"},
        ),
        201,
    )
    assert copied["id"] != confirmed["id"]
    assert copied["source_note_id"] == confirmed["id"]
    assert copied["original_text"] == confirmed["confirmed_text"]
    assert copied["status"] == "draft"

    skipped = value(api_client.post(f"/api/patient-notes/{copied['id']}/skip", headers=headers))
    repeated_skip = value(
        api_client.post(f"/api/patient-notes/{copied['id']}/skip", headers=headers)
    )
    assert skipped["status"] == "skipped"
    assert repeated_skip["confirmed_at"] == skipped["confirmed_at"]


def test_empty_confirmation_and_cross_patient_access_are_rejected(
    api_client: TestClient,
) -> None:
    owner = auth_headers(api_client, "note-first")
    stranger = auth_headers(api_client, "note-second")
    note = value(
        api_client.post(
            "/api/patient-notes",
            headers=owner,
            json={"original_text": ""},
        ),
        201,
    )
    empty = api_client.post(f"/api/patient-notes/{note['id']}/confirm", headers=owner)
    assert empty.status_code == 409
    assert empty.json()["error"]["code"] == "PATIENT_NOTE_EMPTY"
    assert (
        api_client.put(
            f"/api/patient-notes/{note['id']}",
            headers=stranger,
            json={"original_text": "changed"},
        ).status_code
        == 404
    )
