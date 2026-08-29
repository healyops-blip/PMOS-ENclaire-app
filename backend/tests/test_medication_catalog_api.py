from __future__ import annotations

from datetime import UTC, datetime

from fastapi.testclient import TestClient

from pomi_backend.data.medication_catalog import (
    CATALOG_DISCLAIMER,
    CATALOG_ENTRIES,
    CATALOG_SOURCE,
    CATALOG_VERSION,
)
from pomi_backend.db import build_session_factory
from pomi_backend.db.models import MedicationCatalogEntry


def _seed_catalog(client: TestClient) -> None:
    now = datetime.now(UTC)
    with build_session_factory(client.app.state.engine)() as session:
        session.add_all(
            [
                MedicationCatalogEntry(
                    **entry,
                    version=CATALOG_VERSION,
                    source=CATALOG_SOURCE,
                    disclaimer=CATALOG_DISCLAIMER,
                    created_at=now,
                    updated_at=now,
                )
                for entry in CATALOG_ENTRIES
            ]
        )
        session.commit()


def _auth(client: TestClient, name: str) -> dict[str, str]:
    password = "Catalog123"
    assert (
        client.post(
            "/api/auth/register", json={"account_name": name, "password": password}
        ).status_code
        == 201
    )
    response = client.post("/api/auth/login", json={"account_name": name, "password": password})
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['session_id']}"}


def test_catalog_requires_auth_and_supports_alias_search(api_client: TestClient) -> None:
    assert api_client.get("/api/medication-catalog").status_code == 401
    headers = _auth(api_client, "catalog-user")
    _seed_catalog(api_client)

    response = api_client.get("/api/medication-catalog", headers=headers)
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["version"] == "2.0"
    assert data["disclaimer"] == CATALOG_DISCLAIMER
    assert len(data["items"]) == 20

    alias = api_client.get("/api/medication-catalog", params={"q": "达英35"}, headers=headers)
    assert [item["id"] for item in alias.json()["data"]["items"]] == [
        "med_ethinylestradiol_cyproterone_acetate"
    ]


def test_standard_and_custom_medications_are_persisted_separately(
    api_client: TestClient,
) -> None:
    headers = _auth(api_client, "catalog-medication-user")
    _seed_catalog(api_client)
    standard = api_client.post(
        "/api/medications",
        headers={**headers, "Idempotency-Key": "catalog-create-0001"},
        json={
            "drug_name": "二甲双胍",
            "standard_drug_id": "med_metformin_hydrochloride",
            "source_category": "prescribed",
        },
    )
    assert standard.status_code == 201
    assert standard.json()["data"]["standard_drug_id"] == "med_metformin_hydrochloride"

    custom = api_client.post(
        "/api/medications",
        headers={**headers, "Idempotency-Key": "catalog-create-0002"},
        json={"drug_name": "我的复合营养粉", "source_category": "supplement"},
    )
    assert custom.status_code == 201
    assert custom.json()["data"]["standard_drug_id"] is None

    invalid = api_client.post(
        "/api/medications",
        headers={**headers, "Idempotency-Key": "catalog-create-0003"},
        json={
            "drug_name": "不存在的标准药品",
            "standard_drug_id": "does-not-exist",
            "source_category": "other_long_term",
        },
    )
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "INVALID_STANDARD_DRUG_ID"
