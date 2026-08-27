"""Medical document lifecycle with immutable revisions and ownership checks."""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from fastapi import UploadFile
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import Document, DocumentRevision, UserAccount
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import DocumentRepository, PatientRepository
from pomi_backend.services.document_storage import private_path, safe_file_name, store_upload


def revision_data(revision: DocumentRevision) -> dict[str, Any]:
    return {
        "id": revision.id,
        "document_id": revision.document_id,
        "revision_number": revision.revision_number,
        "file_hash": revision.file_hash,
        "file_size_bytes": revision.file_size_bytes,
        "mime_type": revision.mime_type,
        "pixel_count": revision.pixel_count,
        "page_count": revision.page_count,
        "replaced_revision_id": revision.replaced_revision_id,
        "replacement_reason": revision.replacement_reason,
        "is_current": revision.is_current,
        "created_at": revision.created_at.isoformat(),
    }


def document_data(document: Document, current_revision: DocumentRevision | None = None) -> dict:
    value = {
        "id": document.id,
        "patient_id": document.patient_id,
        "document_type": document.document_type,
        "original_file_name": document.original_file_name,
        "mime_type": document.mime_type,
        "file_size_bytes": document.file_size_bytes,
        "pixel_count": document.pixel_count,
        "page_count": document.page_count,
        "file_hash": document.file_hash,
        "current_revision_id": document.current_revision_id,
        "upload_status": document.upload_status,
        "uploaded_at": document.uploaded_at.isoformat(),
        "updated_at": document.updated_at.isoformat(),
        "deleted_at": document.deleted_at.isoformat() if document.deleted_at else None,
        "purge_after": document.purge_after.isoformat() if document.purge_after else None,
    }
    if current_revision is not None:
        value["current_revision"] = revision_data(current_revision)
    return value


class DocumentService:
    def __init__(self, session: Session, account: UserAccount, storage_root: Path) -> None:
        self.session = session
        self.account = account
        self.storage_root = storage_root
        self.patient = PatientRepository(session).get_or_create(account.uid)
        self.repository = DocumentRepository(session, self.patient.patient_id)

    def owned(self, document_id: str, *, include_deleted: bool = False) -> Document:
        document = self.repository.get(document_id, include_deleted=include_deleted)
        if document is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Document was not found.", 404)
        return document

    def detail(self, document: Document) -> dict:
        revision = self.repository.revision(document.id, document.current_revision_id)
        if revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Current revision was not found.", 404)
        return document_data(document, revision)

    def upload(
        self,
        upload: UploadFile,
        *,
        document_type: str,
        idempotency_key: str,
        processing_notice_version: str | None,
    ) -> Document:
        existing = self.repository.find_upload(self.account.uid, idempotency_key)
        if existing is not None:
            return existing
        document_id = new_uuid()
        revision_id = new_uuid()
        stored = store_upload(
            upload,
            storage_root=self.storage_root,
            document_id=document_id,
            revision_id=revision_id,
        )
        accepted_at = utc_now() if processing_notice_version else None
        document = Document(
            id=document_id,
            patient_id=self.patient.patient_id,
            document_type=document_type,
            original_file_name=safe_file_name(upload.filename),
            mime_type=stored.mime_type,
            file_size_bytes=stored.size,
            pixel_count=stored.pixel_count,
            page_count=stored.page_count,
            file_hash=stored.sha256,
            current_revision_id=revision_id,
            uploaded_by_uid=self.account.uid,
            idempotency_key=idempotency_key,
            processing_notice_version=processing_notice_version,
            processing_notice_accepted_at=accepted_at,
        )
        revision = DocumentRevision(
            id=revision_id,
            document_id=document_id,
            revision_number=1,
            storage_path=stored.relative_path,
            file_hash=stored.sha256,
            file_size_bytes=stored.size,
            mime_type=stored.mime_type,
            pixel_count=stored.pixel_count,
            page_count=stored.page_count,
            created_by_uid=self.account.uid,
        )
        try:
            self.repository.add(document, revision)
            self.session.commit()
            self.session.refresh(document)
            return document
        except IntegrityError:
            self.session.rollback()
            stored.path.unlink(missing_ok=True)
            existing = self.repository.find_upload(self.account.uid, idempotency_key)
            if existing is not None:
                return existing
            raise
        except Exception:
            self.session.rollback()
            stored.path.unlink(missing_ok=True)
            raise

    def list(
        self, document_type: str | None, cursor: datetime | None, limit: int
    ) -> list[Document]:
        return self.repository.list(document_type=document_type, cursor=cursor, limit=limit)

    def replace(
        self,
        document_id: str,
        upload: UploadFile,
        *,
        reason: str,
        expected_revision_id: str,
        idempotency_key: str,
    ) -> DocumentRevision:
        document = self.owned(document_id)
        repeated = self.repository.find_revision_request(document.id, idempotency_key)
        if repeated is not None:
            return repeated
        if document.current_revision_id != expected_revision_id:
            raise BusinessError(
                "RESOURCE_VERSION_CONFLICT", "The document revision has changed.", 409
            )
        previous = self.repository.revision(document.id, document.current_revision_id)
        if previous is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Current revision was not found.", 404)
        revision_id = new_uuid()
        stored = store_upload(
            upload,
            storage_root=self.storage_root,
            document_id=document.id,
            revision_id=revision_id,
        )
        try:
            claimed = self.session.execute(
                update(Document)
                .where(
                    Document.id == document.id,
                    Document.patient_id == self.patient.patient_id,
                    Document.current_revision_id == expected_revision_id,
                    Document.deleted_at.is_(None),
                )
                .values(
                    original_file_name=safe_file_name(upload.filename),
                    mime_type=stored.mime_type,
                    file_size_bytes=stored.size,
                    pixel_count=stored.pixel_count,
                    page_count=stored.page_count,
                    file_hash=stored.sha256,
                    current_revision_id=revision_id,
                    updated_at=utc_now(),
                )
            )
            if claimed.rowcount != 1:
                self.session.rollback()
                stored.path.unlink(missing_ok=True)
                repeated = self.repository.find_revision_request(document.id, idempotency_key)
                if repeated is not None:
                    return repeated
                raise BusinessError(
                    "RESOURCE_VERSION_CONFLICT", "The document revision has changed.", 409
                )
            revision = DocumentRevision(
                id=revision_id,
                document_id=document.id,
                revision_number=self.repository.next_revision_number(document.id),
                storage_path=stored.relative_path,
                file_hash=stored.sha256,
                file_size_bytes=stored.size,
                mime_type=stored.mime_type,
                pixel_count=stored.pixel_count,
                page_count=stored.page_count,
                replaced_revision_id=previous.id,
                replacement_reason=reason,
                idempotency_key=idempotency_key,
                created_by_uid=self.account.uid,
            )
            self.session.execute(
                update(DocumentRevision)
                .where(
                    DocumentRevision.id == previous.id,
                    DocumentRevision.document_id == document.id,
                    DocumentRevision.is_current.is_(True),
                )
                .values(is_current=False)
            )
            self.session.add(revision)
            self.session.commit()
            self.session.refresh(revision)
            return revision
        except Exception:
            self.session.rollback()
            stored.path.unlink(missing_ok=True)
            raise

    def delete(self, document_id: str) -> Document:
        document = self.owned(document_id)
        document.deleted_at = utc_now()
        document.purge_after = utc_now() + timedelta(days=7)
        document.upload_status = "deleted"
        document.updated_at = utc_now()
        self.session.commit()
        self.session.refresh(document)
        return document

    def file(self, document_id: str, revision_id: str) -> tuple[Path, DocumentRevision, Document]:
        document = self.owned(document_id)
        revision = self.repository.revision(document.id, revision_id)
        if revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Revision was not found.", 404)
        return private_path(self.storage_root, revision.storage_path), revision, document


def purge_deleted_documents(
    session: Session,
    storage_root: Path,
    *,
    now: datetime,
    is_revision_referenced: Callable[[str], bool] | None = None,
) -> int:
    """Remove expired, unreferenced files while keeping audit metadata."""

    referenced = is_revision_referenced or (lambda _: False)
    documents = list(
        session.scalars(
            select(Document).where(
                Document.deleted_at.is_not(None),
                Document.purge_after <= now,
            )
        )
    )
    removed = 0
    for document in documents:
        revisions = list(
            session.scalars(
                select(DocumentRevision).where(DocumentRevision.document_id == document.id)
            )
        )
        for revision in revisions:
            if referenced(revision.id):
                continue
            path = (storage_root / revision.storage_path).resolve()
            if storage_root.resolve() in path.parents and path.is_file():
                path.unlink()
                removed += 1
        document.purge_after = None
    session.commit()
    return removed
