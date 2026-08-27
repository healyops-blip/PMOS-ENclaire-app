from __future__ import annotations

from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image


def auth_headers(client: TestClient, account_name: str) -> dict[str, str]:
    password = "DocumentPass123"
    assert (
        client.post(
            "/api/auth/register",
            json={"account_name": account_name, "password": password},
        ).status_code
        == 201
    )
    login = client.post(
        "/api/auth/login",
        json={"account_name": account_name, "password": password},
    )
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def image_bytes(color: tuple[int, int, int] = (248, 244, 252)) -> bytes:
    output = BytesIO()
    Image.new("RGB", (320, 240), color=color).save(output, format="PNG")
    return output.getvalue()


def payload(response, status_code: int = 200):
    assert response.status_code == status_code, response.text
    body = response.json()
    assert body["success"] is True
    return body["data"]


def test_document_upload_revision_download_and_delete(api_client: TestClient) -> None:
    headers = auth_headers(api_client, "document-user")
    headers["Idempotency-Key"] = "document-upload-001"
    upload = payload(
        api_client.post(
            "/api/documents",
            headers=headers,
            data={"document_type": "lab_report"},
            files={"file": ("lab.png", image_bytes(), "image/png")},
        ),
        201,
    )
    assert upload["mime_type"] == "image/png"
    assert upload["pixel_count"] == 320 * 240
    assert len(upload["file_hash"]) == 64

    repeated = payload(
        api_client.post(
            "/api/documents",
            headers=headers,
            data={"document_type": "lab_report"},
            files={"file": ("ignored.png", image_bytes((1, 2, 3)), "image/png")},
        ),
        201,
    )
    assert repeated["id"] == upload["id"]

    listing = payload(api_client.get("/api/documents", headers=headers))
    assert [item["id"] for item in listing["items"]] == [upload["id"]]

    original = api_client.get(
        f"/api/documents/{upload['id']}/revisions/{upload['current_revision_id']}/file",
        headers=headers,
    )
    assert original.status_code == 200
    assert original.content == image_bytes()

    replaced = payload(
        api_client.post(
            f"/api/documents/{upload['id']}/revisions",
            headers={
                "Authorization": headers["Authorization"],
                "Idempotency-Key": "document-revision-001",
            },
            data={
                "replacement_reason": "clearer scan",
                "expected_current_revision_id": upload["current_revision_id"],
            },
            files={"file": ("lab-clear.png", image_bytes((10, 20, 30)), "image/png")},
        ),
        201,
    )
    assert replaced["id"] != upload["current_revision_id"]
    assert replaced["revision_number"] == 2
    revisions = payload(api_client.get(f"/api/documents/{upload['id']}/revisions", headers=headers))
    assert [revision["revision_number"] for revision in revisions] == [2, 1]
    assert revisions[0]["is_current"] is True
    assert revisions[1]["is_current"] is False

    deleted = payload(api_client.delete(f"/api/documents/{upload['id']}", headers=headers))
    assert deleted["deleted"] is True
    assert payload(api_client.get("/api/documents", headers=headers))["items"] == []


def test_document_validation_and_account_isolation(api_client: TestClient) -> None:
    first_headers = auth_headers(api_client, "document-first")
    second_headers = auth_headers(api_client, "document-second")
    first_headers["Idempotency-Key"] = "document-upload-002"
    document = payload(
        api_client.post(
            "/api/documents",
            headers=first_headers,
            data={"document_type": "outpatient_record"},
            files={"file": ("record.png", image_bytes(), "image/png")},
        ),
        201,
    )
    forbidden = api_client.get(f"/api/documents/{document['id']}", headers=second_headers)
    assert forbidden.status_code == 404
    assert forbidden.json()["error"]["code"] == "RESOURCE_NOT_FOUND"

    invalid_headers = dict(second_headers)
    invalid_headers["Idempotency-Key"] = "document-upload-003"
    invalid = api_client.post(
        "/api/documents",
        headers=invalid_headers,
        data={"document_type": "lab_report"},
        files={"file": ("fake.png", b"not an image", "image/png")},
    )
    assert invalid.status_code == 415
    assert invalid.json()["error"]["code"] == "UNSUPPORTED_FORMAT"
