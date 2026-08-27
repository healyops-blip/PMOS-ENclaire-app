from __future__ import annotations

from datetime import timedelta
from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image
from pypdf import PdfWriter

from pomi_backend.db.models import Document
from pomi_backend.db.models.auth import utc_now
from pomi_backend.services.documents import purge_deleted_documents


def auth_headers(client: TestClient, account_name: str) -> dict[str, str]:
    password = "DocumentPass123"
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


def image_bytes(*, orientation: int | None = None) -> bytes:
    output = BytesIO()
    image = Image.new("RGB", (40, 20), color=(248, 244, 252))
    exif = image.getexif()
    if orientation is not None:
        exif[274] = orientation
    image.save(output, format="JPEG", exif=exif)
    return output.getvalue()


def two_page_pdf() -> bytes:
    output = BytesIO()
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    writer.add_blank_page(width=200, height=200)
    writer.write(output)
    return output.getvalue()


def one_page_pdf() -> bytes:
    output = BytesIO()
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    writer.write(output)
    return output.getvalue()


def data(response, status_code: int = 200):
    assert response.status_code == status_code, response.text
    return response.json()["data"]


def test_upload_revision_private_download_and_delete(api_client: TestClient) -> None:
    headers = auth_headers(api_client, "document-owner")
    uploaded = data(
        api_client.post(
            "/api/documents",
            headers={**headers, "Idempotency-Key": "document-upload-001"},
            data={
                "document_type": "lab_report",
                "external_processing_consent_version": "ocr-notice-v1",
            },
            files={"file": ("..\\lab.bin", image_bytes(orientation=6), "application/octet-stream")},
        ),
        201,
    )
    assert uploaded["original_file_name"] == "lab.bin"
    assert uploaded["mime_type"] == "image/jpeg"
    assert uploaded["pixel_count"] == 800
    assert len(uploaded["file_hash"]) == 64

    original = api_client.get(
        f"/api/documents/{uploaded['id']}/revisions/{uploaded['current_revision_id']}/file",
        headers=headers,
    )
    assert original.status_code == 200
    assert original.headers["etag"] == f'"{uploaded["file_hash"]}"'
    assert original.headers["cache-control"] == "private, no-store"
    with Image.open(BytesIO(original.content)) as normalized:
        assert normalized.size == (20, 40)

    replacement = data(
        api_client.post(
            f"/api/documents/{uploaded['id']}/revisions",
            headers={**headers, "Idempotency-Key": "document-revision-001"},
            data={
                "replacement_reason": "clearer scan",
                "expected_current_revision_id": uploaded["current_revision_id"],
            },
            files={"file": ("clear.png", _png_bytes(), "image/png")},
        ),
        201,
    )
    assert replacement["revision_number"] == 2
    revisions = data(api_client.get(f"/api/documents/{uploaded['id']}/revisions", headers=headers))
    assert [item["revision_number"] for item in revisions] == [2, 1]
    assert revisions[0]["is_current"] is True
    assert revisions[1]["is_current"] is False

    repeated = data(
        api_client.post(
            f"/api/documents/{uploaded['id']}/revisions",
            headers={**headers, "Idempotency-Key": "document-revision-001"},
            data={
                "replacement_reason": "clearer scan",
                "expected_current_revision_id": uploaded["current_revision_id"],
            },
            files={"file": ("ignored.png", _png_bytes(), "image/png")},
        ),
        201,
    )
    assert repeated["id"] == replacement["id"]

    deleted = data(api_client.delete(f"/api/documents/{uploaded['id']}", headers=headers))
    assert deleted["deleted"] is True
    assert deleted["document_id"] == uploaded["id"]
    assert len(deleted["retained_revision_ids"]) == 2
    assert data(api_client.get("/api/documents", headers=headers))["items"] == []


def _png_bytes() -> bytes:
    output = BytesIO()
    Image.new("RGB", (32, 24), color=(10, 20, 30)).save(output, format="PNG")
    return output.getvalue()


def test_validation_isolation_and_cleanup_retention(api_client: TestClient) -> None:
    first = auth_headers(api_client, "document-first")
    second = auth_headers(api_client, "document-second")
    document = data(
        api_client.post(
            "/api/documents",
            headers={**first, "Idempotency-Key": "document-upload-002"},
            data={"document_type": "outpatient_record"},
            files={"file": ("record.png", _png_bytes(), "image/png")},
        ),
        201,
    )
    assert api_client.get(f"/api/documents/{document['id']}", headers=second).status_code == 404

    invalid = api_client.post(
        "/api/documents",
        headers={**second, "Idempotency-Key": "document-upload-003"},
        data={"document_type": "lab_report"},
        files={"file": ("fake.jpg", b"not an image", "image/jpeg")},
    )
    assert invalid.status_code == 415
    assert invalid.json()["error"]["code"] == "UNSUPPORTED_FORMAT"
    multi = api_client.post(
        "/api/documents",
        headers={**second, "Idempotency-Key": "document-upload-004"},
        data={"document_type": "lab_report"},
        files={"file": ("two.pdf", two_page_pdf(), "application/pdf")},
    )
    assert multi.status_code == 415
    assert multi.json()["error"]["code"] == "MULTI_PAGE_PDF"

    data(api_client.delete(f"/api/documents/{document['id']}", headers=first))
    with api_client.app.state.session_factory() as session:
        stored = session.get(Document, document["id"])
        assert stored is not None
        stored.purge_after = utc_now() - timedelta(seconds=1)
        session.commit()
        assert (
            purge_deleted_documents(
                session,
                api_client.app.state.settings.storage_root,
                now=utc_now(),
                is_revision_referenced=lambda _: True,
            )
            == 0
        )
        assert (
            purge_deleted_documents(
                session,
                api_client.app.state.settings.storage_root,
                now=utc_now(),
            )
            == 1
        )


def test_all_document_types_and_single_page_pdf_are_supported(api_client: TestClient) -> None:
    headers = auth_headers(api_client, "document-types")
    for index, document_type in enumerate(
        ("lab_report", "medical_order", "imaging_text_report", "outpatient_record")
    ):
        file = (
            (f"material-{index}.pdf", one_page_pdf(), "application/pdf")
            if index == 2
            else (f"material-{index}.png", _png_bytes(), "image/png")
        )
        uploaded = data(
            api_client.post(
                "/api/documents",
                headers={**headers, "Idempotency-Key": f"document-type-{index:02d}"},
                data={"document_type": document_type},
                files={"file": file},
            ),
            201,
        )
        assert uploaded["document_type"] == document_type
        assert uploaded["page_count"] == 1

    oversized = api_client.post(
        "/api/documents",
        headers={**headers, "Idempotency-Key": "document-oversized"},
        data={"document_type": "lab_report"},
        files={"file": ("large.png", b"x" * (20 * 1024 * 1024 + 1), "image/png")},
    )
    assert oversized.status_code == 413
    assert oversized.json()["error"]["code"] == "FILE_TOO_LARGE"
