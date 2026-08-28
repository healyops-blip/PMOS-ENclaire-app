from __future__ import annotations

from fastapi.testclient import TestClient


def register_and_login(client: TestClient, account_name: str) -> dict[str, str]:
    password = "ProfilePass123"
    assert (
        client.post(
            "/api/auth/register", json={"account_name": account_name, "password": password}
        ).status_code
        == 201
    )
    login = client.post(
        "/api/auth/login", json={"account_name": account_name, "password": password}
    )
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def data(response, status_code: int = 200):
    assert response.status_code == status_code, response.text
    body = response.json()
    assert body["success"] is True
    assert body["request_id"].startswith("req_")
    return body["data"]


def test_profile_onboarding_and_nullable_visit_date_are_persistent(
    api_client: TestClient,
) -> None:
    headers = register_and_login(api_client, "profile-owner")
    profile = data(api_client.get("/api/patient/profile", headers=headers))
    assert profile["onboarding_completed"] is False
    assert profile["next_visit_date"] is None

    updated = data(
        api_client.put(
            "/api/patient/profile",
            headers=headers,
            json={
                "nickname": "Pomi User",
                "birth_year": 1996,
                "gender": "female",
                "height_cm": 165.5,
                "diagnosis_year": 2024,
                "primary_condition": "PCOS",
                "next_visit_date": None,
                "health_goal": "Prepare follow-up materials",
                "complete_onboarding": True,
                "updated_at": profile["updated_at"],
            },
        )
    )
    assert updated["id"] == profile["id"]
    assert updated["birth_year"] == 1996
    assert updated["onboarding_completed"] is True
    assert updated["next_visit_date"] is None
    assert updated["onboarding_completed_at"] is not None

    completed_at = updated["onboarding_completed_at"]
    edited = data(
        api_client.put(
            "/api/patient/profile",
            headers=headers,
            json={
                "nickname": "Pomi User Edited",
                "complete_onboarding": True,
                "updated_at": updated["updated_at"],
            },
        )
    )
    assert edited["onboarding_completed"] is True
    assert edited["onboarding_completed_at"] == completed_at

    account = api_client.get("/api/auth/me", headers=headers)
    assert account.status_code == 200
    assert account.json()["onboarding_completed"] is True
    restored = data(api_client.get("/api/patient/profile", headers=headers))
    assert restored["nickname"] == "Pomi User Edited"


def test_profile_scope_conflict_and_validation(api_client: TestClient) -> None:
    first_headers = register_and_login(api_client, "profile-first")
    second_headers = register_and_login(api_client, "profile-second")
    first = data(api_client.get("/api/patient/profile", headers=first_headers))
    second = data(api_client.get("/api/patient/profile", headers=second_headers))
    assert first["id"] != second["id"]

    changed = data(
        api_client.put(
            "/api/patient/profile",
            headers=first_headers,
            json={"nickname": "First", "updated_at": first["updated_at"]},
        )
    )
    assert changed["nickname"] == "First"
    conflict = api_client.put(
        "/api/patient/profile",
        headers=first_headers,
        json={"nickname": "Stale", "updated_at": first["updated_at"]},
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "RESOURCE_VERSION_CONFLICT"

    invalid = api_client.put(
        "/api/patient/profile",
        headers=second_headers,
        json={"birth_year": 2101, "updated_at": second["updated_at"]},
    )
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "VALIDATION_ERROR"

    unauthenticated = api_client.get("/api/patient/profile")
    assert unauthenticated.status_code == 401
    assert unauthenticated.json()["error"]["code"] == "AUTHENTICATION_REQUIRED"
