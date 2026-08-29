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
from pomi_backend.db.models import (
    Document,
    DocumentDisplayAsset,
    DocumentRevision,
    OCRResult,
    OCRTask,
    UserAccount,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import DocumentRepository, PatientRepository
from pomi_backend.services.document_storage import private_path, safe_file_name, store_upload
from pomi_backend.services.watermarks import (
    ASSET_TYPE,
    WATERMARK_VERSION,
    DocumentWatermarkService,
    display_asset_data,
)


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
        return self.data(document, revision)

    def data(
        self,
        document: Document,
        current_revision: DocumentRevision | None = None,
    ) -> dict[str, Any]:
        """Return document metadata plus the latest OCR task needed by the client."""

        latest_task = self.session.scalar(
            select(OCRTask)
            .where(
                OCRTask.patient_id == self.patient.patient_id,
                OCRTask.document_id == document.id,
            )
            .order_by(OCRTask.created_at.desc(), OCRTask.id.desc())
            .limit(1)
        )
        revision = current_revision
        if revision is None and document.current_revision_id:
            revision = self.repository.revision(document.id, document.current_revision_id)
        display_asset = (
            self.repository.display_asset(
                document.id,
                revision.id,
                asset_type=ASSET_TYPE,
                watermark_version=WATERMARK_VERSION,
            )
            if revision is not None
            else None
        )
        # 把最新 OCR 结果的 validated_draft（识别出的临床字段）合并进文档详情，
        # 使记录页能展示影像检查所见/结论、门诊主诉/诊断、医嘱药品等丰富字段。
        ocr_draft: dict[str, Any] = {}
        if latest_task is not None:
            latest_result = self.session.scalar(
                select(OCRResult)
                .where(OCRResult.task_id == latest_task.id)
                .order_by(OCRResult.created_at.desc())
                .limit(1)
            )
            if latest_result is not None and isinstance(latest_result.validated_draft, dict):
                ocr_draft = {
                    key: value
                    for key, value in latest_result.validated_draft.items()
                    if value is not None
                }
        return {
            **document_data(document, current_revision),
            "latest_ocr_task_id": latest_task.id if latest_task is not None else None,
            "latest_ocr_status": latest_task.status if latest_task is not None else None,
            "latest_ocr_result_source": (
                latest_task.result_source if latest_task is not None else None
            ),
            "display_asset": display_asset_data(display_asset),
            **ocr_draft,
        }

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

    def display_asset(
        self,
        document_id: str,
        revision_id: str,
    ) -> tuple[DocumentDisplayAsset | None, DocumentRevision, Document]:
        document = self.owned(document_id)
        revision = self.repository.revision(document.id, revision_id)
        if revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Revision was not found.", 404)
        asset = self.repository.display_asset(
            document.id,
            revision.id,
            asset_type=ASSET_TYPE,
            watermark_version=WATERMARK_VERSION,
        )
        return asset, revision, document

    def retry_display_asset(
        self,
        document_id: str,
        revision_id: str,
    ) -> DocumentDisplayAsset:
        asset, revision, document = self.display_asset(document_id, revision_id)
        return DocumentWatermarkService(self.session, self.storage_root).generate(
            document,
            revision,
            force=asset is None or asset.status != "ready",
        )

    def display_file(
        self,
        document_id: str,
        revision_id: str,
    ) -> tuple[Path, DocumentDisplayAsset, Document]:
        asset, _, document = self.display_asset(document_id, revision_id)
        if asset is None:
            raise BusinessError(
                "RESOURCE_NOT_FOUND",
                "The watermarked display image was not found.",
                404,
            )
        path = DocumentWatermarkService(self.session, self.storage_root).file(asset)
        return path, asset, document


def purge_deleted_documents(
    session: Session,
    storage_root: Path,
    *,
    now: datetime,
    is_revision_referenced: Callable[[str], bool] | None = None,
) -> int:
    """Remove expired, unreferenced files while keeping audit metadata."""

    if is_revision_referenced is None:
        from pomi_backend.db.models import ReportSource

        def referenced(revision_id: str) -> bool:
            return (
                session.scalar(
                    select(ReportSource.id)
                    .where(ReportSource.document_revision_id == revision_id)
                    .limit(1)
                )
                is not None
            )

    else:
        referenced = is_revision_referenced
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
            display_assets = list(
                session.scalars(
                    select(DocumentDisplayAsset).where(
                        DocumentDisplayAsset.document_revision_id == revision.id
                    )
                )
            )
            for asset in display_assets:
                if asset.storage_path:
                    display_path = (storage_root / asset.storage_path).resolve()
                    if storage_root.resolve() in display_path.parents and display_path.is_file():
                        display_path.unlink()
                        removed += 1
                asset.status = "purged"
                asset.storage_path = None
                asset.updated_at = now
        document.purge_after = None
    session.commit()
    return removed
