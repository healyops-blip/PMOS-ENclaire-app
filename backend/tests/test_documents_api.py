from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from io import BytesIO
from threading import Barrier, Lock

from fastapi.testclient import TestClient
from PIL import Image
from pypdf import PdfWriter
from pytest import MonkeyPatch

from pomi_backend.db.models import Document, DocumentRevision
from pomi_backend.db.models.auth import utc_now
from pomi_backend.repositories.documents import DocumentRepository
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
    display_endpoint = (
        f"/api/documents/{uploaded['id']}/revisions/{uploaded['current_revision_id']}/display"
    )
    assert data(api_client.get(display_endpoint, headers=headers)) is None
    premature = api_client.post(f"{display_endpoint}/retry", headers=headers)
    assert premature.status_code == 409
    assert premature.json()["error"]["code"] == "WATERMARK_OCR_NOT_READY"

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
    inaccessible = (
        ("get", f"/api/documents/{document['id']}"),
        ("get", f"/api/documents/{document['id']}/revisions"),
        (
            "get",
            f"/api/documents/{document['id']}/revisions/{document['current_revision_id']}/file",
        ),
        ("delete", f"/api/documents/{document['id']}"),
    )
    for method, path in inaccessible:
        assert api_client.request(method, path, headers=second).status_code == 404
    assert (
        api_client.post(
            f"/api/documents/{document['id']}/revisions",
            headers={**second, "Idempotency-Key": "cross-owner-replace"},
            data={
                "replacement_reason": "must not cross owner boundary",
                "expected_current_revision_id": document["current_revision_id"],
            },
            files={"file": ("cross.png", _png_bytes(), "image/png")},
        ).status_code
        == 404
    )

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

    replacement = data(
        api_client.post(
            f"/api/documents/{document['id']}/revisions",
            headers={**first, "Idempotency-Key": "document-cleanup-revision"},
            data={
                "replacement_reason": "cleanup coverage",
                "expected_current_revision_id": document["current_revision_id"],
            },
            files={"file": ("replacement.png", _png_bytes(), "image/png")},
        ),
        201,
    )
    data(api_client.delete(f"/api/documents/{document['id']}", headers=first))
    with api_client.app.state.session_factory() as session:
        stored = session.get(Document, document["id"])
        assert stored is not None
        stored.purge_after = utc_now() - timedelta(seconds=1)
        session.commit()
        revisions = list(
            session.query(DocumentRevision)
            .filter(DocumentRevision.document_id == document["id"])
            .all()
        )
        paths = {
            revision.id: api_client.app.state.settings.storage_root / revision.storage_path
            for revision in revisions
        }
        assert all(path.is_file() for path in paths.values())
        assert (
            purge_deleted_documents(
                session,
                api_client.app.state.settings.storage_root,
                now=utc_now(),
                is_revision_referenced=lambda revision_id: (
                    revision_id == document["current_revision_id"]
                ),
            )
            == 1
        )
        assert paths[document["current_revision_id"]].is_file()
        assert not paths[replacement["id"]].exists()
        session.refresh(stored)
        assert stored.purge_after is None


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


def test_concurrent_replacements_allow_only_one_current_revision(
    api_client: TestClient, monkeypatch: MonkeyPatch
) -> None:
    headers = auth_headers(api_client, "document-concurrency")
    document = data(
        api_client.post(
            "/api/documents",
            headers={**headers, "Idempotency-Key": "concurrent-upload"},
            data={"document_type": "lab_report"},
            files={"file": ("initial.png", _png_bytes(), "image/png")},
        ),
        201,
    )
    barrier = Barrier(2)
    lock = Lock()
    initial_calls = 0
    original = DocumentRepository.find_revision_request

    def synchronized_find(
        repository: DocumentRepository, document_id: str, idempotency_key: str
    ) -> DocumentRevision | None:
        nonlocal initial_calls
        result = original(repository, document_id, idempotency_key)
        with lock:
            initial_calls += 1
            synchronize = initial_calls <= 2
        if synchronize:
            barrier.wait(timeout=5)
        return result

    monkeypatch.setattr(DocumentRepository, "find_revision_request", synchronized_find)

    def replace(index: int):
        return api_client.post(
            f"/api/documents/{document['id']}/revisions",
            headers={**headers, "Idempotency-Key": f"concurrent-revision-{index}"},
            data={
                "replacement_reason": f"concurrent replacement {index}",
                "expected_current_revision_id": document["current_revision_id"],
            },
            files={"file": (f"replacement-{index}.png", _png_bytes(), "image/png")},
        )

    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(executor.map(replace, (1, 2)))

    assert sorted(response.status_code for response in responses) == [201, 409]
    revisions = data(api_client.get(f"/api/documents/{document['id']}/revisions", headers=headers))
    assert [revision["revision_number"] for revision in revisions] == [2, 1]
    assert sum(revision["is_current"] for revision in revisions) == 1
