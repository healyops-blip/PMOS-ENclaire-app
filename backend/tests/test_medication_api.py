from __future__ import annotations

from datetime import date

from fastapi.testclient import TestClient
from sqlalchemy import func, select

from pomi_backend.db import build_session_factory
from pomi_backend.db.models import Medication, MedicationDaily


def authenticated(client: TestClient, name: str = "medication-user") -> dict[str, str]:
    password = "Medication123"
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
    body = response.json()
    assert body["success"] is True
    assert body["request_id"].startswith("req_")
    return body["data"]


def create_medication(
    client: TestClient,
    headers: dict[str, str],
    *,
    key: str = "medication-create-0001",
) -> dict:
    return response_data(
        client.post(
            "/api/medications",
            headers={**headers, "Idempotency-Key": key},
            json={
                "drug_name": "Metformin",
                "source_category": "prescribed",
                "specification": "500 mg",
                "dosage_value": 500,
                "dosage_unit": "mg",
                "frequency": "twice daily",
                "route": "oral",
                "start_date": "2026-08-01",
                "event_date": "2026-08-01",
            },
        ),
        201,
    )


def test_adjustment_creates_version_and_keeps_complete_event_chain(
    api_client: TestClient,
) -> None:
    headers = authenticated(api_client)
    original = create_medication(api_client, headers)

    paused = response_data(
        api_client.put(
            f"/api/medications/{original['id']}",
            headers=headers,
            json={
                "event_type": "paused",
                "event_date": "2026-08-05",
                "updated_at": original["updated_at"],
            },
        )
    )
    out_of_order = api_client.put(
        f"/api/medications/{original['id']}",
        headers=headers,
        json={
            "event_type": "resumed",
            "event_date": "2026-08-04",
            "updated_at": paused["updated_at"],
        },
    )
    assert out_of_order.status_code == 422
    assert out_of_order.json()["error"]["code"] == "INVALID_EVENT_DATE"
    resumed = response_data(
        api_client.put(
            f"/api/medications/{original['id']}",
            headers=headers,
            json={
                "event_type": "resumed",
                "event_date": "2026-08-08",
                "updated_at": paused["updated_at"],
            },
        )
    )
    adjusted = response_data(
        api_client.put(
            f"/api/medications/{original['id']}",
            headers=headers,
            json={
                "event_type": "adjusted",
                "event_date": "2026-08-10",
                "dosage_value": 850,
                "updated_at": resumed["updated_at"],
                "change_reason": "doctor changed dose",
            },
        )
    )
    replacement = adjusted

    assert replacement["id"] != original["id"]
    assert replacement["replaces_medication_id"] == original["id"]
    assert replacement["dosage_value"] == 850
    listed = response_data(api_client.get("/api/medications", headers=headers))
    assert set(listed["groups"]) == {"prescribed", "supplement", "other_long_term"}
    assert len(listed["groups"]["prescribed"]) == 1
    assert listed["groups"]["prescribed"][0]["id"] == replacement["id"]

    events = response_data(
        api_client.get(f"/api/medications/{replacement['id']}/events", headers=headers)
    )
    assert [event["event_type"] for event in events] == [
        "created",
        "paused",
        "resumed",
        "adjusted",
    ]
    assert events[-1]["old_instruction"]["dosage_value"] == 500.0
    assert events[-1]["new_instruction"]["dosage_value"] == 850.0

    stopped = response_data(
        api_client.put(
            f"/api/medications/{replacement['id']}",
            headers=headers,
            json={
                "event_type": "stopped",
                "event_date": "2026-08-12",
                "stop_source": "written_order",
                "updated_at": replacement["updated_at"],
            },
        )
    )
    assert stopped["current_status"] == "stopped"
    events = response_data(
        api_client.get(f"/api/medications/{replacement['id']}/events", headers=headers)
    )
    assert [event["event_type"] for event in events][-2:] == ["adjusted", "stopped"]
    assert events[-1]["stop_source"] == "written_order"

    conflict = api_client.put(
        f"/api/medications/{original['id']}",
        headers=headers,
        json={
            "event_type": "paused",
            "event_date": "2026-08-11",
            "updated_at": original["updated_at"],
        },
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "RESOURCE_VERSION_CONFLICT"


def test_daily_state_is_idempotent_and_unrecorded_is_not_stored(
    api_client: TestClient,
    api_engine,
) -> None:
    headers = authenticated(api_client, "daily-user")
    medication = create_medication(api_client, headers, key="medication-create-0002")
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 2)
    url = f"/api/medications/{medication['id']}/daily-status"

    first = response_data(
        api_client.put(
            url,
            headers=headers,
            json={"record_date": "2026-08-02", "intake_status": "taken"},
        )
    )
    repeated = response_data(
        api_client.put(
            url,
            headers=headers,
            json={"record_date": "2026-08-02", "intake_status": "taken"},
        )
    )
    missed = response_data(
        api_client.put(
            url,
            headers=headers,
            json={"record_date": "2026-08-02", "intake_status": "missed"},
        )
    )
    assert first["id"] == repeated["id"] == missed["id"]
    assert first["recorded_at"] == repeated["recorded_at"]
    assert missed["intake_status"] == "missed"
    with build_session_factory(api_engine)() as session:
        assert session.scalar(select(func.count()).select_from(MedicationDaily)) == 1

    medication_page = response_data(api_client.get("/api/medications", headers=headers))
    assert medication_page["server_date"] == "2026-08-02"
    cleared = response_data(
        api_client.put(
            url,
            headers=headers,
            json={"record_date": "2026-08-02", "intake_status": "unrecorded"},
        )
    )
    assert cleared["id"] is None
    assert cleared["recorded_at"] is None
    with build_session_factory(api_engine)() as session:
        assert session.scalar(select(func.count()).select_from(MedicationDaily)) == 0

    dynamic = response_data(
        api_client.get("/api/medication-daily?from=2026-08-01&to=2026-08-31", headers=headers)
    )
    assert [item["record_date"] for item in dynamic] == ["2026-08-01", "2026-08-02"]
    assert all(item["intake_status"] == "unrecorded" for item in dynamic)
    assert all(item["id"] is None for item in dynamic)


def test_month_stats_respect_pause_resume_adjustment_and_stop_boundaries(
    api_client: TestClient,
    api_engine,
) -> None:
    headers = authenticated(api_client, "stats-user")
    original = create_medication(api_client, headers, key="medication-create-0003")

    api_client.app.state.business_date_provider = lambda: date(2026, 8, 2)
    response_data(
        api_client.put(
            f"/api/medications/{original['id']}/daily-status",
            headers=headers,
            json={"record_date": "2026-08-02", "intake_status": "taken"},
        )
    )
    paused = response_data(
        api_client.put(
            f"/api/medications/{original['id']}",
            headers=headers,
            json={
                "event_type": "paused",
                "event_date": "2026-08-05",
                "updated_at": original["updated_at"],
            },
        )
    )
    resumed = response_data(
        api_client.put(
            f"/api/medications/{original['id']}",
            headers=headers,
            json={
                "event_type": "resumed",
                "event_date": "2026-08-08",
                "updated_at": paused["updated_at"],
            },
        )
    )
    replacement = response_data(
        api_client.put(
            f"/api/medications/{original['id']}",
            headers=headers,
            json={
                "event_type": "adjusted",
                "event_date": "2026-08-10",
                "frequency": "once daily",
                "updated_at": resumed["updated_at"],
            },
        )
    )
    response_data(
        api_client.put(
            f"/api/medications/{replacement['id']}",
            headers=headers,
            json={
                "event_type": "stopped",
                "event_date": "2026-08-12",
                "stop_source": "written_order",
                "updated_at": replacement["updated_at"],
            },
        )
    )
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 20)

    stats = response_data(
        api_client.get("/api/medication-daily?from=2026-08-01&to=2026-08-31", headers=headers)
    )
    assert sum(item["intake_status"] == "taken" for item in stats) == 1
    assert sum(item["intake_status"] == "missed" for item in stats) == 0
    assert sum(item["intake_status"] == "unrecorded" for item in stats) == 7
    assert len(stats) == 8
    assert {item["record_date"] for item in stats} == {
        "2026-08-01",
        "2026-08-02",
        "2026-08-03",
        "2026-08-04",
        "2026-08-08",
        "2026-08-09",
        "2026-08-10",
        "2026-08-11",
    }

    with build_session_factory(api_engine)() as session:
        versions = list(session.scalars(select(Medication).order_by(Medication.start_date)))
        assert versions[0].dosage_value == 500
        assert versions[0].end_date == date(2026, 8, 9)
        assert versions[1].replaces_medication_id == versions[0].id


def test_cross_account_medication_is_hidden(api_client: TestClient) -> None:
    first = authenticated(api_client, "private-owner")
    medication = create_medication(api_client, first, key="medication-create-0004")
    second = authenticated(api_client, "other-owner")
    response = api_client.get(f"/api/medications/{medication['id']}/events", headers=second)
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "RESOURCE_NOT_FOUND"


def test_medication_api_requires_bearer_session(api_client: TestClient) -> None:
    response = api_client.get("/api/medications")
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert response.json()["error"]["code"] == "AUTHENTICATION_REQUIRED"
