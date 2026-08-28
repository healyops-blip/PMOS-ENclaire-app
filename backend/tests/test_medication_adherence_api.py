from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import date
from threading import Barrier

from fastapi.testclient import TestClient
from sqlalchemy import func, select

from pomi_backend.db import build_session_factory
from pomi_backend.db.models import MedicationDaily


def authenticated(client: TestClient, name: str) -> dict[str, str]:
    password = "Adherence123"
    assert (
        client.post(
            "/api/auth/register", json={"account_name": name, "password": password}
        ).status_code
        == 201
    )
    login = client.post("/api/auth/login", json={"account_name": name, "password": password})
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def response_data(response, expected_status: int = 200):
    assert response.status_code == expected_status, response.text
    return response.json()["data"]


def create_medication(client: TestClient, headers: dict[str, str], *, key: str) -> dict:
    return response_data(
        client.post(
            "/api/medications",
            headers={**headers, "Idempotency-Key": key},
            json={
                "drug_name": "Metformin",
                "source_category": "prescribed",
                "start_date": "2026-08-01",
                "event_date": "2026-08-01",
            },
        ),
        201,
    )


def test_seven_day_edit_window_and_future_boundary(api_client: TestClient) -> None:
    headers = authenticated(api_client, "adherence-boundary")
    medication = create_medication(api_client, headers, key="adherence-boundary-medication")[
        "medication"
    ]
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 10)
    url = f"/api/medications/{medication['id']}/daily-status"

    for record_date in ("2026-08-10", "2026-08-04"):
        saved = response_data(
            api_client.put(
                url,
                headers=headers,
                json={"record_date": record_date, "intake_status": "taken"},
            )
        )
        assert saved["record_date"] == record_date
        assert saved["editable"] is True
        assert saved["editable_from"] == "2026-08-04"

    too_old = api_client.put(
        url,
        headers=headers,
        json={"record_date": "2026-08-03", "intake_status": "taken"},
    )
    assert too_old.status_code == 409
    error = too_old.json()["error"]
    assert error["code"] == "HISTORICAL_DAILY_STATUS_READ_ONLY"
    assert error["message"] == (
        "Medication status older than the seven-day edit window is read-only."
    )
    assert error["details"] == {
        "business_date": "2026-08-10",
        "editable_from": "2026-08-04",
    }

    future = api_client.put(
        url,
        headers=headers,
        json={"record_date": "2026-08-11", "intake_status": "taken"},
    )
    assert future.status_code == 409
    assert future.json()["error"]["code"] == "FUTURE_DAILY_STATUS_NOT_ALLOWED"


def test_backfill_is_idempotent_audited_and_updates_month_summary(
    api_client: TestClient,
    api_engine,
) -> None:
    headers = authenticated(api_client, "adherence-idempotency")
    medication = create_medication(api_client, headers, key="adherence-idempotency-medication")[
        "medication"
    ]
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 10)
    url = f"/api/medications/{medication['id']}/daily-status"
    payload = {"record_date": "2026-08-05", "intake_status": "missed"}

    first = response_data(api_client.put(url, headers=headers, json=payload))
    repeated = response_data(api_client.put(url, headers=headers, json=payload))

    assert repeated["id"] == first["id"]
    assert repeated["recorded_at"] == first["recorded_at"]
    assert repeated["recorded_by_uid"] == first["recorded_by_uid"]
    assert repeated["record_date"] == "2026-08-05"
    assert repeated["recorded_at"] is not None
    assert repeated["month_summary"]["missed_count"] == 1
    assert repeated["month_summary"]["taken_count"] == 0

    changed = response_data(
        api_client.put(
            url,
            headers=headers,
            json={"record_date": "2026-08-05", "intake_status": "taken"},
        )
    )
    assert changed["month_summary"]["taken_count"] == 1
    assert changed["month_summary"]["missed_count"] == 0

    cleared = response_data(
        api_client.put(
            url,
            headers=headers,
            json={"record_date": "2026-08-05", "intake_status": "unrecorded"},
        )
    )
    assert cleared["id"] is None
    assert cleared["month_summary"]["unrecorded_count"] == 10
    with build_session_factory(api_engine)() as session:
        assert session.scalar(select(func.count()).select_from(MedicationDaily)) == 0


def test_history_marks_recent_dates_editable_and_older_dates_read_only(
    api_client: TestClient,
) -> None:
    headers = authenticated(api_client, "adherence-history")
    medication = create_medication(api_client, headers, key="adherence-history-medication")[
        "medication"
    ]
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 10)

    history = response_data(
        api_client.get(
            "/api/medication-daily",
            headers=headers,
            params={
                "from": "2026-08-01",
                "to": "2026-08-10",
                "medication_id": medication["id"],
            },
        )
    )
    by_date = {item["record_date"]: item for item in history["items"]}
    assert history["business_date"] == "2026-08-10"
    assert history["editable_from"] == "2026-08-04"
    assert by_date["2026-08-03"]["editable"] is False
    assert by_date["2026-08-04"]["editable"] is True
    assert by_date["2026-08-10"]["editable"] is True


def test_adherence_history_and_mutations_are_isolated_by_session_uid(
    api_client: TestClient,
) -> None:
    owner = authenticated(api_client, "adherence-private-owner")
    stranger = authenticated(api_client, "adherence-private-stranger")
    medication = create_medication(
        api_client,
        owner,
        key="adherence-private-medication",
    )["medication"]
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 10)
    url = f"/api/medications/{medication['id']}/daily-status"
    response_data(
        api_client.put(
            url,
            headers=owner,
            json={"record_date": "2026-08-05", "intake_status": "taken"},
        )
    )

    hidden_history = api_client.get(
        "/api/medication-daily",
        headers=stranger,
        params={
            "from": "2026-08-04",
            "to": "2026-08-10",
            "medication_id": medication["id"],
        },
    )
    assert hidden_history.status_code == 404
    assert hidden_history.json()["error"]["code"] == "RESOURCE_NOT_FOUND"

    hidden_write = api_client.put(
        url,
        headers=stranger,
        json={"record_date": "2026-08-05", "intake_status": "missed"},
    )
    assert hidden_write.status_code == 404
    assert hidden_write.json()["error"]["code"] == "RESOURCE_NOT_FOUND"

    stranger_history = response_data(
        api_client.get(
            "/api/medication-daily",
            headers=stranger,
            params={"from": "2026-08-04", "to": "2026-08-10"},
        )
    )
    assert stranger_history["items"] == []

    owner_history = response_data(
        api_client.get(
            "/api/medication-daily",
            headers=owner,
            params={
                "from": "2026-08-04",
                "to": "2026-08-10",
                "medication_id": medication["id"],
            },
        )
    )
    assert {item["intake_status"] for item in owner_history["items"]} >= {"taken"}


def test_revoked_session_cannot_read_or_backfill_adherence(
    api_client: TestClient,
) -> None:
    headers = authenticated(api_client, "adherence-revoked")
    medication = create_medication(
        api_client,
        headers,
        key="adherence-revoked-medication",
    )["medication"]
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 10)
    assert api_client.post("/api/auth/logout", headers=headers).status_code == 204

    history = api_client.get(
        "/api/medication-daily?from=2026-08-04&to=2026-08-10",
        headers=headers,
    )
    mutation = api_client.put(
        f"/api/medications/{medication['id']}/daily-status",
        headers=headers,
        json={"record_date": "2026-08-05", "intake_status": "taken"},
    )
    assert history.status_code == mutation.status_code == 401
    assert history.json()["error"]["code"] == "AUTHENTICATION_REQUIRED"
    assert mutation.json()["error"]["code"] == "AUTHENTICATION_REQUIRED"


def test_concurrent_identical_backfills_create_one_audited_row(
    api_client: TestClient,
    api_engine,
) -> None:
    headers = authenticated(api_client, "adherence-concurrent")
    medication = create_medication(
        api_client,
        headers,
        key="adherence-concurrent-medication",
    )["medication"]
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 10)
    url = f"/api/medications/{medication['id']}/daily-status"
    workers = 6
    barrier = Barrier(workers)

    def backfill() -> tuple[int, dict]:
        barrier.wait()
        response = api_client.put(
            url,
            headers=headers,
            json={"record_date": "2026-08-05", "intake_status": "taken"},
        )
        return response.status_code, response.json()

    with ThreadPoolExecutor(max_workers=workers) as executor:
        results = list(executor.map(lambda _: backfill(), range(workers)))

    assert {status for status, _ in results} == {200}
    records = [body["data"] for _, body in results]
    assert len({record["id"] for record in records}) == 1
    assert all(record["recorded_at"] for record in records)
    assert all(record["recorded_by_uid"] for record in records)
    with build_session_factory(api_engine)() as session:
        assert session.scalar(select(func.count()).select_from(MedicationDaily)) == 1
