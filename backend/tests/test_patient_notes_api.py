from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier, Lock

from fastapi.testclient import TestClient
from pytest import LogCaptureFixture, MonkeyPatch

from pomi_backend.services.patient_notes import PatientNoteService


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
    assert confirmed["confirmed_by_uid"] is not None

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
    api_client: TestClient, caplog: LogCaptureFixture
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
    missing = api_client.post("/api/patient-notes", headers=owner, json={})
    assert missing.status_code == 422
    empty = api_client.post(f"/api/patient-notes/{note['id']}/confirm", headers=owner)
    assert empty.status_code == 409
    assert empty.json()["error"]["code"] == "PATIENT_NOTE_EMPTY"
    requests = (
        ("put", f"/api/patient-notes/{note['id']}", {"original_text": "changed"}),
        ("post", f"/api/patient-notes/{note['id']}/confirm", None),
        ("post", f"/api/patient-notes/{note['id']}/skip", None),
        ("post", f"/api/patient-notes/{note['id']}/copy", {}),
    )
    for method, path, payload in requests:
        assert api_client.request(method, path, headers=stranger, json=payload).status_code == 404
    assert value(api_client.get("/api/patient-notes/latest", headers=stranger)) is None
    assert "changed" not in caplog.text


def test_concurrent_confirmation_is_idempotent(
    api_client: TestClient, monkeypatch: MonkeyPatch
) -> None:
    headers = auth_headers(api_client, "note-concurrent")
    note = value(
        api_client.post(
            "/api/patient-notes",
            headers=headers,
            json={"original_text": "Keep this exact text."},
        ),
        201,
    )
    barrier = Barrier(2)
    lock = Lock()
    calls = 0
    original = PatientNoteService.owned

    def synchronized_owned(service: PatientNoteService, note_id: str):
        nonlocal calls
        owned = original(service, note_id)
        with lock:
            calls += 1
            synchronize = calls <= 2
        if synchronize:
            barrier.wait(timeout=5)
        return owned

    monkeypatch.setattr(PatientNoteService, "owned", synchronized_owned)

    def confirm(_: int):
        return api_client.post(f"/api/patient-notes/{note['id']}/confirm", headers=headers)

    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(executor.map(confirm, (1, 2)))

    decisions = [value(response) for response in responses]
    assert {decision["status"] for decision in decisions} == {"confirmed"}
    assert len({decision["confirmed_at"] for decision in decisions}) == 1
    assert {decision["confirmed_text"] for decision in decisions} == {"Keep this exact text."}
