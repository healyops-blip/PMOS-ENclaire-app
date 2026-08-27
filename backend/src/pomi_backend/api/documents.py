"""Authenticated medical-document and immutable-revision API."""

from typing import Annotated, Literal

from fastapi import APIRouter, File, Form, Header, Query, Request, UploadFile, status
from fastapi.responses import FileResponse

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import DocumentServiceDependency
from pomi_backend.services.documents import document_data, revision_data

router = APIRouter(prefix="/api/documents", tags=["documents"])
DocumentType = Literal["lab_report", "medical_order", "imaging_text_report", "outpatient_record"]
UploadStatus = Literal["uploaded", "processing", "ready", "failed", "deleted"]
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)]


@router.post("", status_code=status.HTTP_201_CREATED)
def upload_document(
    request: Request,
    service: DocumentServiceDependency,
    file: Annotated[UploadFile, File()],
    document_type: Annotated[DocumentType, Form()],
    idempotency_key: IdempotencyKey,
    encounter_id: Annotated[str | None, Form()] = None,
    external_processing_consent_version: Annotated[str | None, Form()] = None,
) -> dict:
    del external_processing_consent_version
    document = service.upload(
        file,
        document_type=document_type,
        encounter_id=encounter_id,
        idempotency_key=idempotency_key,
    )
    return success(request, service.detail(document))


@router.get("")
def list_documents(
    request: Request,
    service: DocumentServiceDependency,
    document_type: DocumentType | None = None,
    encounter_id: str | None = None,
    upload_status: UploadStatus | None = None,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> dict:
    documents = service.list(document_type, encounter_id, upload_status, limit, cursor)
    page = documents[:limit]
    return success(
        request,
        {
            "items": [document_data(document) for document in page],
            "next_cursor": page[-1].uploaded_at.isoformat() if len(documents) > limit else None,
            "has_more": len(documents) > limit,
        },
    )


@router.get("/{document_id}")
def get_document(
    document_id: str,
    request: Request,
    service: DocumentServiceDependency,
) -> dict:
    document = service.owned_document(document_id)
    return success(request, service.detail(document))


@router.delete("/{document_id}")
def delete_document(
    document_id: str,
    request: Request,
    service: DocumentServiceDependency,
) -> dict:
    document = service.delete(document_id)
    return success(
        request,
        {"deleted": True, "deleted_at": document.deleted_at.isoformat()},
    )


@router.get("/{document_id}/revisions")
def list_revisions(
    document_id: str,
    request: Request,
    service: DocumentServiceDependency,
) -> dict:
    return success(
        request,
        [revision_data(item) for item in service.revisions(document_id)],
    )


@router.post("/{document_id}/revisions", status_code=status.HTTP_201_CREATED)
def replace_document(
    document_id: str,
    request: Request,
    service: DocumentServiceDependency,
    file: Annotated[UploadFile, File()],
    replacement_reason: Annotated[str, Form(min_length=1, max_length=500)],
    idempotency_key: IdempotencyKey,
    expected_current_revision_id: Annotated[str | None, Form()] = None,
) -> dict:
    return success(
        request,
        revision_data(
            service.replace(
                document_id,
                file,
                replacement_reason,
                expected_current_revision_id,
                idempotency_key,
            )
        ),
    )


@router.get("/{document_id}/revisions/{revision_id}/file", response_class=FileResponse)
def get_revision_file(
    document_id: str,
    revision_id: str,
    service: DocumentServiceDependency,
) -> FileResponse:
    path, document = service.file(document_id, revision_id)
    return FileResponse(
        path,
        media_type=document.mime_type,
        filename=document.original_file_name,
    )
