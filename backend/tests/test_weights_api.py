from __future__ import annotations

from typing import Any

from fastapi.testclient import TestClient
from httpx import Response


def response_data(response: Response) -> Any:
    return response.json()["data"]


def auth_headers(client: TestClient, account_name: str) -> dict[str, str]:
    password = "weightpass1"
    registered = client.post(
        "/api/auth/register",
        json={"account_name": account_name, "password": password},
    )
    assert registered.status_code == 201
    login = client.post(
        "/api/auth/login",
        json={"account_name": account_name, "password": password},
    )
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def test_weight_create_same_day_update_and_sorted_trend(api_client: TestClient) -> None:
    headers = auth_headers(api_client, "weight-owner")

    latest = api_client.post(
        "/api/weights",
        headers=headers,
        json={"record_date": "2026-08-27", "weight_kg": 63.5},
    )
    earliest = api_client.post(
        "/api/weights",
        headers=headers,
        json={"record_date": "2026-08-05", "weight_kg": 64.0},
    )
    same_day = api_client.post(
        "/api/weights",
        headers=headers,
        json={"record_date": "2026-08-27", "weight_kg": 63.2},
    )

    assert latest.status_code == earliest.status_code == 201
    assert same_day.status_code == 200
    assert response_data(same_day)["id"] == response_data(latest)["id"]
    assert response_data(same_day)["weight_kg"] == 63.2
    assert same_day.json()["success"] is True
    assert same_day.json()["request_id"] == same_day.headers["x-request-id"]

    trend = api_client.get("/api/weights", headers=headers)
    assert trend.status_code == 200
    assert [item["record_date"] for item in response_data(trend)] == [
        "2026-08-05",
        "2026-08-27",
    ]
    assert [item["weight_kg"] for item in response_data(trend)] == [64.0, 63.2]

    filtered = api_client.get(
        "/api/weights?from=2026-08-10&to=2026-08-31",
        headers=headers,
    )
    assert [item["id"] for item in response_data(filtered)] == [response_data(latest)["id"]]


def test_weight_validation_matches_20_to_300_and_one_decimal(api_client: TestClient) -> None:
    headers = auth_headers(api_client, "weight-range")

    for day, value in (("2026-08-01", 20.0), ("2026-08-02", 300.0)):
        response = api_client.post(
            "/api/weights",
            headers=headers,
            json={"record_date": day, "weight_kg": value},
        )
        assert response.status_code == 201

    for value in (19.9, 300.1, 63.55, "not-a-number", None):
        response = api_client.post(
            "/api/weights",
            headers=headers,
            json={"record_date": "2026-08-03", "weight_kg": value},
        )
        assert response.status_code == 422


def test_weight_update_and_patient_ownership_isolation(api_client: TestClient) -> None:
    first_headers = auth_headers(api_client, "weight-first")
    second_headers = auth_headers(api_client, "weight-second")
    created = api_client.post(
        "/api/weights",
        headers=first_headers,
        json={"record_date": "2026-08-20", "weight_kg": 70.1},
    )
    created_data = response_data(created)

    assert response_data(api_client.get("/api/weights", headers=second_headers)) == []
    forbidden_update = api_client.put(
        f"/api/weights/{created_data['id']}",
        headers=second_headers,
        json={"record_date": "2026-08-20", "weight_kg": 55.0},
    )
    assert forbidden_update.status_code == 404

    own_update = api_client.put(
        f"/api/weights/{created_data['id']}",
        headers=first_headers,
        json={
            "record_date": "2026-08-21",
            "weight_kg": 69.9,
            "updated_at": created_data["updated_at"],
        },
    )
    assert own_update.status_code == 200
    assert response_data(own_update)["record_date"] == "2026-08-21"
    assert response_data(own_update)["weight_kg"] == 69.9

    second = api_client.post(
        "/api/weights",
        headers=first_headers,
        json={"record_date": "2026-08-22", "weight_kg": 69.8},
    )
    second_data = response_data(second)
    conflict = api_client.put(
        f"/api/weights/{second_data['id']}",
        headers=first_headers,
        json={
            "record_date": "2026-08-21",
            "weight_kg": 69.7,
            "updated_at": second_data["updated_at"],
        },
    )
    assert conflict.status_code == 409


def test_weights_require_authentication_and_reject_reverse_range(api_client: TestClient) -> None:
    assert api_client.get("/api/weights").status_code == 401
    headers = auth_headers(api_client, "weight-query")
    invalid = api_client.get(
        "/api/weights?from=2026-08-20&to=2026-08-01",
        headers=headers,
    )
    assert invalid.status_code == 422
