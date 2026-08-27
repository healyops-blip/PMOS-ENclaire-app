"""Document metadata, immutable revision, and private-file operations."""

from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path

from fastapi import UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import Document, DocumentRevision, Encounter, OcrTask, UserAccount
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.services.document_storage import private_path, store_upload
from pomi_backend.services.health_records import HealthRecordService


def document_data(document: Document) -> dict:
    return {
        "id": document.id,
        "patient_id": document.patient_id,
        "encounter_id": document.encounter_id,
        "document_type": document.document_type,
        "original_file_name": document.original_file_name,
        "mime_type": document.mime_type,
        "file_size_bytes": document.file_size_bytes,
        "pixel_count": document.pixel_count,
        "file_hash": document.file_hash,
        "page_count": document.page_count,
        "upload_status": document.upload_status,
        "current_revision_id": document.current_revision_id,
        "uploaded_at": document.uploaded_at.isoformat(),
        "deleted_at": document.deleted_at.isoformat() if document.deleted_at else None,
        "purge_after": document.purge_after.isoformat() if document.purge_after else None,
    }


def revision_data(revision: DocumentRevision) -> dict:
    return {
        "id": revision.id,
        "document_id": revision.document_id,
        "revision_number": revision.revision_number,
        "file_hash": revision.file_hash,
        "file_size_bytes": revision.file_size_bytes,
        "replaced_revision_id": revision.replaced_revision_id,
        "replacement_reason": revision.replacement_reason,
        "is_current": revision.is_current,
        "created_at": revision.created_at.isoformat(),
    }


def ocr_task_data(task: OcrTask) -> dict:
    return {
        "id": task.id,
        "document_id": task.document_id,
        "document_revision_id": task.document_revision_id,
        "document_type": task.document_type,
        "task_status": task.task_status,
        "attempt_count": task.attempt_count,
        "max_attempts": task.max_attempts,
        "queued_at": task.queued_at.isoformat(),
        "started_at": task.started_at.isoformat() if task.started_at else None,
        "finished_at": task.finished_at.isoformat() if task.finished_at else None,
        "processing_ms": task.processing_ms,
        "error_code": task.error_code,
        "error_message": task.error_message,
        "result_source": task.result_source,
        "progress": task.progress,
    }


class DocumentService:
    def __init__(self, session: Session, account: UserAccount, storage_root: Path) -> None:
        self.session = session
        self.account = account
        self.storage_root = storage_root
        self.health = HealthRecordService(session, account)

    def owned_document(self, document_id: str, *, include_deleted: bool = False) -> Document:
        statement = select(Document).where(
            Document.id == document_id,
            Document.patient_id == self.health.profile().patient_id,
        )
        if not include_deleted:
            statement = statement.where(Document.deleted_at.is_(None))
        document = self.session.scalar(statement)
        if document is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Document was not found.", 404)
        return document

    def detail(self, document: Document) -> dict:
        revision = self.session.get(DocumentRevision, document.current_revision_id)
        if revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Current revision is missing.", 404)
        task = self.session.scalar(
            select(OcrTask)
            .where(OcrTask.document_id == document.id)
            .order_by(OcrTask.queued_at.desc())
            .limit(1)
        )
        return {
            **document_data(document),
            "current_revision": revision_data(revision),
            "latest_ocr_task": ocr_task_data(task) if task else None,
        }

    def upload(
        self,
        upload: UploadFile,
        *,
        document_type: str,
        encounter_id: str | None,
        idempotency_key: str,
    ) -> Document:
        existing = self.session.scalar(
            select(Document).where(
                Document.uploaded_by_uid == self.account.uid,
                Document.idempotency_key == idempotency_key,
            )
        )
        if existing is not None:
            return existing
        profile = self.health.profile()
        if encounter_id is not None:
            encounter = self.session.scalar(
                select(Encounter).where(
                    Encounter.id == encounter_id,
                    Encounter.patient_id == profile.patient_id,
                )
            )
            if encounter is None:
                raise BusinessError("RESOURCE_NOT_FOUND", "Encounter was not found.", 404)
        document_id = new_uuid()
        revision_id = new_uuid()
        stored = store_upload(
            upload,
            storage_root=self.storage_root,
            document_id=document_id,
            revision_id=revision_id,
        )
        try:
            document = Document(
                id=document_id,
                patient_id=profile.patient_id,
                encounter_id=encounter_id,
                document_type=document_type,
                original_file_name=(upload.filename or "upload")[:255],
                mime_type=stored.mime_type,
                file_size_bytes=stored.size,
                pixel_count=stored.pixel_count,
                page_count=stored.page_count,
                file_hash=stored.sha256,
                upload_status="uploaded",
                current_revision_id=revision_id,
                uploaded_by_uid=self.account.uid,
                idempotency_key=idempotency_key,
            )
            revision = DocumentRevision(
                id=revision_id,
                document_id=document_id,
                revision_number=1,
                storage_path=stored.relative_path,
                file_hash=stored.sha256,
                file_size_bytes=stored.size,
                created_by_uid=self.account.uid,
            )
            self.session.add_all([document, revision])
            self.session.commit()
            self.session.refresh(document)
            return document
        except Exception:
            self.session.rollback()
            stored.path.unlink(missing_ok=True)
            raise

    def list(
        self,
        document_type: str | None,
        encounter_id: str | None,
        upload_status: str | None,
        limit: int,
        cursor: str | None,
    ) -> list[Document]:
        statement = select(Document).where(
            Document.patient_id == self.health.profile().patient_id,
            Document.deleted_at.is_(None),
        )
        if document_type is not None:
            statement = statement.where(Document.document_type == document_type)
        if encounter_id is not None:
            statement = statement.where(Document.encounter_id == encounter_id)
        if upload_status is not None:
            statement = statement.where(Document.upload_status == upload_status)
        if cursor is not None:
            try:
                cursor_time = datetime.fromisoformat(cursor)
            except ValueError as exc:
                raise BusinessError("VALIDATION_ERROR", "Invalid cursor.", 422) from exc
            statement = statement.where(Document.uploaded_at < cursor_time)
        return list(
            self.session.scalars(statement.order_by(Document.uploaded_at.desc()).limit(limit + 1))
        )

    def delete(self, document_id: str) -> Document:
        document = self.owned_document(document_id)
        document.deleted_at = utc_now()
        document.purge_after = utc_now() + timedelta(days=7)
        document.upload_status = "deleted"
        self.session.commit()
        self.session.refresh(document)
        return document

    def revisions(self, document_id: str) -> list[DocumentRevision]:
        self.owned_document(document_id)
        return list(
            self.session.scalars(
                select(DocumentRevision)
                .where(DocumentRevision.document_id == document_id)
                .order_by(DocumentRevision.revision_number.desc())
            )
        )

    def replace(
        self,
        document_id: str,
        upload: UploadFile,
        replacement_reason: str,
        expected_current_revision_id: str | None,
        idempotency_key: str,
    ) -> DocumentRevision:
        document = self.owned_document(document_id)
        existing = self.session.scalar(
            select(DocumentRevision).where(
                DocumentRevision.document_id == document.id,
                DocumentRevision.idempotency_key == idempotency_key,
            )
        )
        if existing is not None:
            return existing
        if (
            expected_current_revision_id is not None
            and expected_current_revision_id != document.current_revision_id
        ):
            raise BusinessError(
                "RESOURCE_VERSION_CONFLICT",
                "The document revision has changed.",
                409,
            )
        previous = self.session.get(DocumentRevision, document.current_revision_id)
        if previous is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Current revision is missing.", 404)
        revision_id = new_uuid()
        stored = store_upload(
            upload,
            storage_root=self.storage_root,
            document_id=document.id,
            revision_id=revision_id,
        )
        revision_number = self.session.scalar(
            select(func.max(DocumentRevision.revision_number)).where(
                DocumentRevision.document_id == document.id
            )
        )
        try:
            previous.is_current = False
            revision = DocumentRevision(
                id=revision_id,
                document_id=document.id,
                revision_number=(revision_number or 0) + 1,
                storage_path=stored.relative_path,
                file_hash=stored.sha256,
                file_size_bytes=stored.size,
                replaced_revision_id=previous.id,
                replacement_reason=replacement_reason,
                idempotency_key=idempotency_key,
                is_current=True,
                created_by_uid=self.account.uid,
            )
            self.session.add(revision)
            document.original_file_name = (upload.filename or document.original_file_name)[:255]
            document.mime_type = stored.mime_type
            document.file_size_bytes = stored.size
            document.pixel_count = stored.pixel_count
            document.page_count = stored.page_count
            document.file_hash = stored.sha256
            document.current_revision_id = revision.id
            document.upload_status = "uploaded"
            self.session.commit()
            self.session.refresh(revision)
            return revision
        except Exception:
            self.session.rollback()
            stored.path.unlink(missing_ok=True)
            raise

    def file(self, document_id: str, revision_id: str) -> tuple[Path, Document]:
        document = self.owned_document(document_id)
        revision = self.session.scalar(
            select(DocumentRevision).where(
                DocumentRevision.id == revision_id,
                DocumentRevision.document_id == document.id,
            )
        )
        if revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Revision was not found.", 404)
        return private_path(self.storage_root, revision.storage_path), document
