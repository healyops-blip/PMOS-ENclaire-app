"""Patient-scoped medical document repository."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from pomi_backend.db.models.documents import (
    Document,
    DocumentDisplayAsset,
    DocumentRevision,
)


class DocumentRepository:
    def __init__(self, session: Session, patient_id: str) -> None:
        self.session = session
        self.patient_id = patient_id

    def get(self, document_id: str, *, include_deleted: bool = False) -> Document | None:
        statement = select(Document).where(
            Document.id == document_id,
            Document.patient_id == self.patient_id,
        )
        if not include_deleted:
            statement = statement.where(Document.deleted_at.is_(None))
        return self.session.scalar(statement)

    def find_upload(self, account_uid: str, idempotency_key: str) -> Document | None:
        return self.session.scalar(
            select(Document).where(
                Document.uploaded_by_uid == account_uid,
                Document.idempotency_key == idempotency_key,
            )
        )

    def list(
        self,
        *,
        document_type: str | None = None,
        cursor: datetime | None = None,
        limit: int = 20,
    ) -> list[Document]:
        statement = select(Document).where(
            Document.patient_id == self.patient_id,
            Document.deleted_at.is_(None),
        )
        if document_type is not None:
            statement = statement.where(Document.document_type == document_type)
        if cursor is not None:
            statement = statement.where(Document.uploaded_at < cursor)
        return list(
            self.session.scalars(statement.order_by(Document.uploaded_at.desc()).limit(limit + 1))
        )

    def add(self, document: Document, revision: DocumentRevision) -> None:
        if document.patient_id != self.patient_id or revision.document_id != document.id:
            raise ValueError("document does not match repository scope")
        self.session.add_all([document, revision])
        self.session.flush()

    def revision(self, document_id: str, revision_id: str) -> DocumentRevision | None:
        if self.get(document_id, include_deleted=True) is None:
            return None
        return self.session.scalar(
            select(DocumentRevision).where(
                DocumentRevision.id == revision_id,
                DocumentRevision.document_id == document_id,
            )
        )

    def revisions(self, document_id: str) -> list[DocumentRevision]:
        if self.get(document_id, include_deleted=True) is None:
            return []
        return list(
            self.session.scalars(
                select(DocumentRevision)
                .where(DocumentRevision.document_id == document_id)
                .order_by(DocumentRevision.revision_number.desc())
            )
        )

    def find_revision_request(
        self, document_id: str, idempotency_key: str
    ) -> DocumentRevision | None:
        return self.session.scalar(
            select(DocumentRevision).where(
                DocumentRevision.document_id == document_id,
                DocumentRevision.idempotency_key == idempotency_key,
            )
        )

    def next_revision_number(self, document_id: str) -> int:
        current = self.session.scalar(
            select(func.max(DocumentRevision.revision_number)).where(
                DocumentRevision.document_id == document_id
            )
        )
        return (current or 0) + 1

    def display_asset(
        self,
        document_id: str,
        revision_id: str,
        *,
        asset_type: str,
        watermark_version: str,
    ) -> DocumentDisplayAsset | None:
        if self.revision(document_id, revision_id) is None:
            return None
        return self.session.scalar(
            select(DocumentDisplayAsset).where(
                DocumentDisplayAsset.document_id == document_id,
                DocumentDisplayAsset.document_revision_id == revision_id,
                DocumentDisplayAsset.asset_type == asset_type,
                DocumentDisplayAsset.watermark_version == watermark_version,
            )
        )
