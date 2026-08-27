from __future__ import annotations

from datetime import UTC, date, datetime

from fastapi.testclient import TestClient


def register_and_login(client: TestClient, account_name: str = "health-user") -> dict[str, str]:
    password = "HealthPass123"
    register = client.post(
        "/api/auth/register",
        json={"account_name": account_name, "password": password},
    )
    assert register.status_code == 201
    login = client.post(
        "/api/auth/login",
        json={"account_name": account_name, "password": password},
    )
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def data(response, status_code: int = 200):
    assert response.status_code == status_code, response.text
    payload = response.json()
    assert payload["success"] is True
    assert payload["request_id"].startswith("req_")
    assert payload["error"] is None
    return payload["data"]


def complete_profile(client: TestClient, headers: dict[str, str]) -> dict:
    profile = data(client.get("/api/patient/profile", headers=headers))
    assert profile["onboarding_completed"] is False
    return data(
        client.put(
            "/api/patient/profile",
            headers=headers,
            json={
                "nickname": "Pomi User",
                "birth_date": "1994-06-10",
                "gender": "female",
                "height_cm": 165,
                "diagnosis_year": 2023,
                "usual_cycle_length_days": 31,
                "last_menstrual_start_date": "2026-08-01",
                "next_visit_date": "2026-09-15",
                "health_goal": "Prepare follow-up materials",
                "accept_external_ocr_notice": True,
                "complete_onboarding": True,
                "updated_at": profile["updated_at"],
            },
        )
    )


def test_profile_tracking_and_dashboard_flow(api_client: TestClient) -> None:
    headers = register_and_login(api_client)
    profile = complete_profile(api_client, headers)
    assert profile["onboarding_completed"] is True
    assert profile["last_menstrual_start_date"] == "2026-08-01"

    current_account = api_client.get("/api/auth/me", headers=headers)
    assert current_account.status_code == 200
    assert current_account.json()["onboarding_completed"] is True

    medication_result = data(
        api_client.post(
            "/api/medications",
            headers={**headers, "Idempotency-Key": "00000001"},
            json={
                "drug_name": "Metformin",
                "specification": "0.5 g",
                "dosage_text": "0.5 g",
                "dosage_value": 0.5,
                "dosage_unit": "g",
                "frequency": "twice daily",
                "route": "oral",
                "start_date": "2026-08-01",
                "source_type": "manual",
                "event_date": "2026-08-01",
            },
        ),
        201,
    )
    medication = medication_result["medication"]
    assert medication_result["event"]["event_type"] == "started"

    daily = data(
        api_client.put(
            f"/api/medications/{medication['id']}/daily-status",
            headers=headers,
            json={"record_date": "2026-08-27", "intake_status": "taken"},
        )
    )
    assert daily["intake_status"] == "taken"

    daily = data(
        api_client.put(
            f"/api/medications/{medication['id']}/daily-status",
            headers=headers,
            json={"record_date": "2026-08-27", "intake_status": "missed"},
        )
    )
    assert daily["id"]
    assert daily["intake_status"] == "missed"

    records = data(
        api_client.get(
            "/api/medication-daily?from=2026-08-01&to=2026-08-31",
            headers=headers,
        )
    )
    assert records["missed_count"] == 1
    assert records["taken_count"] == 0

    updated = data(
        api_client.put(
            f"/api/medications/{medication['id']}",
            headers=headers,
            json={
                "event_type": "adjusted",
                "event_date": "2026-08-28",
                "dosage_text": "1 g",
                "updated_at": medication["updated_at"],
            },
        )
    )
    assert updated["medication"]["dosage_text"] == "1 g"
    events = data(api_client.get(f"/api/medications/{medication['id']}/events", headers=headers))
    assert [event["event_type"] for event in events] == ["adjusted", "started"]

    weight_payload = {
        "measured_at": datetime(2026, 8, 27, 8, tzinfo=UTC).isoformat(),
        "weight_kg": 63.8,
    }
    first_weight = data(api_client.post("/api/weights", headers=headers, json=weight_payload), 201)
    weight_payload["weight_kg"] = 63.5
    second_weight = data(api_client.post("/api/weights", headers=headers, json=weight_payload))
    assert first_weight["id"] == second_weight["id"]
    assert second_weight["weight_kg"] == 63.5

    dashboard = data(api_client.get("/api/dashboard", headers=headers))
    assert dashboard["profile_summary"]["nickname"] == "Pomi User"
    assert dashboard["today_medications"][0]["drug_name"] == "Metformin"


def test_cycle_overlap_and_cross_account_isolation(api_client: TestClient) -> None:
    first_headers = register_and_login(api_client, "first-health-user")
    complete_profile(api_client, first_headers)
    second_headers = register_and_login(api_client, "second-health-user")
    complete_profile(api_client, second_headers)

    cycle = data(
        api_client.post(
            "/api/cycles",
            headers=first_headers,
            json={"start_date": "2026-09-01", "end_date": "2026-09-05"},
        ),
        201,
    )
    assert cycle["duration_days"] == 5
    overlap = api_client.post(
        "/api/cycles",
        headers=first_headers,
        json={"start_date": "2026-09-04", "end_date": "2026-09-07"},
    )
    assert overlap.status_code == 409
    assert overlap.json()["error"]["code"] == "CYCLE_DATE_OVERLAP"

    first_medication = data(
        api_client.post(
            "/api/medications",
            headers={**first_headers, "Idempotency-Key": "00000002"},
            json={
                "drug_name": "Private medication",
                "start_date": date.today().isoformat(),
                "source_type": "manual",
                "event_date": date.today().isoformat(),
            },
        ),
        201,
    )["medication"]
    forbidden = api_client.get(
        f"/api/medications/{first_medication['id']}/events",
        headers=second_headers,
    )
    assert forbidden.status_code == 404
    assert forbidden.json()["error"]["code"] == "RESOURCE_NOT_FOUND"


def test_business_api_requires_bearer_session(api_client: TestClient) -> None:
    response = api_client.get("/api/dashboard")
    assert response.status_code == 401
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "AUTHENTICATION_REQUIRED"
