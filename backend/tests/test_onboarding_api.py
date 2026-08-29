from __future__ import annotations

from fastapi.testclient import TestClient


def _register_and_login(client: TestClient) -> dict[str, str]:
    password = "OnboardingPass123"
    register = client.post(
        "/api/auth/register",
        json={"account_name": "onboarding-owner", "password": password},
    )
    assert register.status_code == 201
    login = client.post(
        "/api/auth/login",
        json={"account_name": "onboarding-owner", "password": password},
    )
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def _data(response, status_code: int = 200):
    assert response.status_code == status_code, response.text
    body = response.json()
    assert body["success"] is True
    return body["data"]


def test_period_duration_survives_onboarding_completion(api_client: TestClient) -> None:
    headers = _register_and_login(api_client)

    _data(
        api_client.put(
            "/api/onboarding/steps/basic",
            headers=headers,
            json={"nickname": "Pomi User", "birth_year": 1997},
        )
    )
    cycle = _data(
        api_client.put(
            "/api/onboarding/steps/cycle",
            headers=headers,
            json={
                "usual_cycle_min_days": 35,
                "usual_cycle_max_days": 45,
                "period_duration_days": 5,
            },
        )
    )
    assert cycle["cycle"]["period_duration_days"] == 5
    _data(
        api_client.put(
            "/api/onboarding/steps/medications",
            headers=headers,
            json={"items": []},
        )
    )

    completed = _data(
        api_client.post(
            "/api/onboarding/complete",
            headers={**headers, "Idempotency-Key": "complete-period-duration"},
        )
    )
    assert completed["account"]["onboarding_completed"] is True
    assert completed["profile"]["period_duration_days"] == 5

    profile = _data(api_client.get("/api/patient/profile", headers=headers))
    assert profile["period_duration_days"] == 5


def test_period_duration_rejects_implausible_values(api_client: TestClient) -> None:
    headers = _register_and_login(api_client)
    response = api_client.put(
        "/api/onboarding/steps/cycle",
        headers=headers,
        json={"period_duration_days": 15},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


def test_basic_draft_keeps_height_and_weight_as_numbers(api_client: TestClient) -> None:
    """Decimal fields must round-trip as JSON numbers, not strings.

    Pydantic serializes Decimal to string in JSON mode by default, which broke
    the draft contract and made the client throw "height_cm 格式异常".
    """
    headers = _register_and_login(api_client)
    basic = _data(
        api_client.put(
            "/api/onboarding/steps/basic",
            headers=headers,
            json={
                "nickname": "Pomi User",
                "birth_year": 1997,
                "height_cm": 165.5,
                "weight_kg": 58.3,
            },
        )
    )
    assert basic["basic"]["height_cm"] == 165.5
    assert isinstance(basic["basic"]["height_cm"], (int, float))
    assert basic["basic"]["weight_kg"] == 58.3
    assert isinstance(basic["basic"]["weight_kg"], (int, float))
