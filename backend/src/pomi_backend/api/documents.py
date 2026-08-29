"""Authenticated medical document and immutable revision API."""

from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, File, Form, Header, Query, Request, UploadFile, status
from fastapi.responses import FileResponse

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import DocumentServiceDependency
from pomi_backend.services.documents import revision_data

router = APIRouter(prefix="/api/documents", tags=["documents"])
DocumentType = Literal["lab_report", "medical_order", "imaging_text_report", "outpatient_record"]
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)]


@router.post("", status_code=status.HTTP_201_CREATED)
def upload_document(
    request: Request,
    service: DocumentServiceDependency,
    file: Annotated[UploadFile, File()],
    document_type: Annotated[DocumentType, Form()],
    idempotency_key: IdempotencyKey,
    external_processing_consent_version: Annotated[str | None, Form(max_length=40)] = None,
) -> dict:
    document = service.upload(
        file,
        document_type=document_type,
        idempotency_key=idempotency_key,
        processing_notice_version=external_processing_consent_version,
    )
    return success(request, service.detail(document))


@router.get("")
def list_documents(
    request: Request,
    service: DocumentServiceDependency,
    document_type: DocumentType | None = None,
    cursor: datetime | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> dict:
    documents = service.list(document_type, cursor, limit)
    page = documents[:limit]
    return success(
        request,
        {
            "items": [service.data(document) for document in page],
            "next_cursor": page[-1].uploaded_at.isoformat() if len(documents) > limit else None,
            "has_more": len(documents) > limit,
        },
    )


@router.get("/{document_id}")
def get_document(document_id: str, request: Request, service: DocumentServiceDependency) -> dict:
    return success(request, service.detail(service.owned(document_id)))


@router.delete("/{document_id}")
def delete_document(document_id: str, request: Request, service: DocumentServiceDependency) -> dict:
    document = service.delete(document_id)
    return success(
        request,
        {
            "document_id": document.id,
            "deleted": True,
            "deleted_at": document.deleted_at.isoformat(),
            "purge_after": document.purge_after.isoformat(),
            "retained_revision_ids": [
                revision.id for revision in service.repository.revisions(document.id)
            ],
        },
    )


@router.get("/{document_id}/revisions")
def list_revisions(document_id: str, request: Request, service: DocumentServiceDependency) -> dict:
    service.owned(document_id)
    return success(
        request,
        [revision_data(revision) for revision in service.repository.revisions(document_id)],
    )


@router.post("/{document_id}/revisions", status_code=status.HTTP_201_CREATED)
def replace_revision(
    document_id: str,
    request: Request,
    service: DocumentServiceDependency,
    file: Annotated[UploadFile, File()],
    replacement_reason: Annotated[str, Form(min_length=1, max_length=500)],
    expected_current_revision_id: Annotated[str, Form()],
    idempotency_key: IdempotencyKey,
) -> dict:
    revision = service.replace(
        document_id,
        file,
        reason=replacement_reason,
        expected_revision_id=expected_current_revision_id,
        idempotency_key=idempotency_key,
    )
    return success(request, revision_data(revision))


@router.get("/{document_id}/revisions/{revision_id}/file", response_class=FileResponse)
def download_revision(
    document_id: str,
    revision_id: str,
    service: DocumentServiceDependency,
) -> FileResponse:
    path, revision, document = service.file(document_id, revision_id)
    return FileResponse(
        path,
        media_type=revision.mime_type,
        filename=document.original_file_name,
        headers={
            "ETag": f'"{revision.file_hash}"',
            "Cache-Control": "private, no-store",
            "X-Content-Type-Options": "nosniff",
        },
    )
