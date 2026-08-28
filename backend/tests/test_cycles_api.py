from __future__ import annotations

from datetime import datetime

from fastapi.testclient import TestClient
from sqlalchemy import Engine, select

from pomi_backend.db import build_session_factory
from pomi_backend.db.models import MenstrualCycle


def authenticated_headers(client: TestClient, account_name: str) -> dict[str, str]:
    password = "cyclepass1"
    registration = client.post(
        "/api/auth/register",
        json={"account_name": account_name, "password": password},
    )
    assert registration.status_code == 201
    login = client.post(
        "/api/auth/login",
        json={"account_name": account_name, "password": password},
    )
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def create_cycle(
    client: TestClient,
    headers: dict[str, str],
    start: str,
    end: str | None,
) -> dict[str, object]:
    response = client.post(
        "/api/cycles",
        headers=headers,
        json={"start_date": start, "end_date": end, "source_type": "manual"},
    )
    assert response.status_code == 201, response.text
    return response.json()["data"]


def test_cycles_require_authentication_and_new_patient_has_empty_history(
    api_client: TestClient,
) -> None:
    assert api_client.get("/api/cycles").status_code == 401
    headers = authenticated_headers(api_client, "cycle-empty")

    response = api_client.get("/api/cycles", headers=headers)

    assert response.status_code == 200
    assert response.json()["data"] == []
    assert response.json()["success"] is True
    assert response.headers["X-Request-ID"] == response.json()["request_id"]


def test_create_open_cycle_and_reject_invalid_or_overlapping_dates(
    api_client: TestClient,
) -> None:
    headers = authenticated_headers(api_client, "cycle-boundaries")
    created = create_cycle(api_client, headers, "2026-08-10", None)

    assert created["end_date"] is None
    assert created["duration_days"] is None
    assert created["cycle_length_days"] is None

    inverted = api_client.post(
        "/api/cycles",
        headers=headers,
        json={"start_date": "2026-08-09", "end_date": "2026-08-08"},
    )
    assert inverted.status_code == 422
    assert inverted.json()["error"]["code"] == "CYCLE_DATE_ORDER_INVALID"
    assert "start date" in inverted.json()["error"]["message"]

    overlapping = api_client.post(
        "/api/cycles",
        headers=headers,
        json={"start_date": "2026-08-12", "end_date": "2026-08-15"},
    )
    assert overlapping.status_code == 409
    assert overlapping.json()["error"]["code"] == "CYCLE_DATE_OVERLAP"
    assert overlapping.json()["error"]["details"]["conflicting_cycle_id"] == created["id"]


def test_list_is_descending_and_edit_recomputes_adjacent_cycle_lengths(
    api_client: TestClient,
) -> None:
    headers = authenticated_headers(api_client, "cycle-lengths")
    oldest = create_cycle(api_client, headers, "2026-05-01", "2026-05-05")
    middle = create_cycle(api_client, headers, "2026-05-30", "2026-06-03")
    newest = create_cycle(api_client, headers, "2026-06-28", "2026-07-02")

    listed = api_client.get("/api/cycles", headers=headers).json()["data"]
    assert [item["id"] for item in listed] == [newest["id"], middle["id"], oldest["id"]]
    assert [item["cycle_length_days"] for item in listed] == [29, 29, None]
    assert listed[0]["duration_days"] == 5

    updated = api_client.put(
        f"/api/cycles/{middle['id']}",
        headers=headers,
        json={
            "start_date": "2026-05-29",
            "end_date": "2026-06-02",
            "flow_level": "medium",
            "note": "补录",
            "updated_at": middle["updated_at"],
        },
    )
    assert updated.status_code == 200
    assert updated.json()["data"]["cycle_length_days"] == 28

    recomputed = api_client.get("/api/cycles", headers=headers).json()["data"]
    assert [item["cycle_length_days"] for item in recomputed] == [30, 28, None]

    may_only = api_client.get(
        "/api/cycles?from=2026-05-15&to=2026-05-31",
        headers=headers,
    )
    assert [item["id"] for item in may_only.json()["data"]] == [middle["id"]]


def test_soft_delete_hides_record_and_other_patient_cannot_mutate_it(
    api_client: TestClient,
    api_engine: Engine,
) -> None:
    owner_headers = authenticated_headers(api_client, "cycle-owner")
    stranger_headers = authenticated_headers(api_client, "cycle-stranger")
    cycle = create_cycle(api_client, owner_headers, "2026-07-01", "2026-07-05")

    forbidden_update = api_client.put(
        f"/api/cycles/{cycle['id']}",
        headers=stranger_headers,
        json={"start_date": "2026-07-02", "end_date": "2026-07-06"},
    )
    assert forbidden_update.status_code == 404
    assert api_client.get("/api/cycles", headers=stranger_headers).json()["data"] == []
    assert (
        api_client.delete(f"/api/cycles/{cycle['id']}", headers=stranger_headers).status_code == 404
    )

    deleted = api_client.delete(f"/api/cycles/{cycle['id']}", headers=owner_headers)
    assert deleted.status_code == 204
    assert api_client.get("/api/cycles", headers=owner_headers).json()["data"] == []
    assert api_client.delete(f"/api/cycles/{cycle['id']}", headers=owner_headers).status_code == 404

    with build_session_factory(api_engine)() as session:
        stored = session.scalar(select(MenstrualCycle).where(MenstrualCycle.id == cycle["id"]))
        assert stored is not None
        assert isinstance(stored.deleted_at, datetime)


def test_update_rejects_stale_timestamp(api_client: TestClient) -> None:
    headers = authenticated_headers(api_client, "cycle-version")
    cycle = create_cycle(api_client, headers, "2026-04-01", "2026-04-05")

    stale = api_client.put(
        f"/api/cycles/{cycle['id']}",
        headers=headers,
        json={
            "start_date": "2026-04-01",
            "end_date": "2026-04-06",
            "updated_at": "2020-01-01T00:00:00Z",
        },
    )

    assert stale.status_code == 409
    assert stale.json()["error"]["code"] == "CYCLE_VERSION_CONFLICT"
