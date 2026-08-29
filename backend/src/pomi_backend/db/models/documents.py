"""Private medical document and immutable revision models."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from pomi_backend.db.base import Base
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.db.types import UTCDateTime


class Document(Base):
    __tablename__ = "document"
    __table_args__ = (
        CheckConstraint(
            "document_type IN "
            "('lab_report', 'medical_order', 'imaging_text_report', 'outpatient_record')",
            name="document_type",
        ),
        CheckConstraint(
            "upload_status IN ('uploaded', 'ready', 'failed', 'deleted')",
            name="document_upload_status",
        ),
        UniqueConstraint(
            "uploaded_by_uid", "idempotency_key", name="uq_document_upload_idempotency"
        ),
        Index("ix_document_patient_uploaded", "patient_id", "uploaded_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    document_type: Mapped[str] = mapped_column(String(32), nullable=False)
    original_file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False)
    file_size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    pixel_count: Mapped[int | None] = mapped_column(Integer)
    page_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    file_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    current_revision_id: Mapped[str] = mapped_column(String(36), nullable=False)
    upload_status: Mapped[str] = mapped_column(String(16), nullable=False, default="uploaded")
    uploaded_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    processing_notice_version: Mapped[str | None] = mapped_column(String(40))
    processing_notice_accepted_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    uploaded_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )
    deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    purge_after: Mapped[datetime | None] = mapped_column(UTCDateTime)


class DocumentRevision(Base):
    __tablename__ = "document_revision"
    __table_args__ = (
        UniqueConstraint("document_id", "revision_number", name="uq_document_revision_number"),
        UniqueConstraint("document_id", "idempotency_key", name="uq_document_revision_idempotency"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="CASCADE"), nullable=False
    )
    revision_number: Mapped[int] = mapped_column(Integer, nullable=False)
    storage_path: Mapped[str] = mapped_column(String(500), nullable=False)
    file_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    file_size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False)
    pixel_count: Mapped[int | None] = mapped_column(Integer)
    page_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    replaced_revision_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("document_revision.id", ondelete="SET NULL")
    )
    replacement_reason: Mapped[str | None] = mapped_column(String(500))
    idempotency_key: Mapped[str | None] = mapped_column(String(128))
    is_current: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class DocumentDisplayAsset(Base):
    """A private, reproducible display derivative of an immutable source revision."""

    __tablename__ = "document_display_asset"
    __table_args__ = (
        CheckConstraint(
            "asset_type IN ('pomi_watermarked_display')",
            name="document_display_asset_type",
        ),
        CheckConstraint(
            "status IN ('processing', 'ready', 'failed', 'unsupported', 'purged')",
            name="document_display_asset_status",
        ),
        UniqueConstraint(
            "document_revision_id",
            "asset_type",
            "watermark_version",
            name="uq_document_display_asset_revision_variant",
        ),
        Index(
            "ix_document_display_asset_document_revision",
            "document_id",
            "document_revision_id",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="CASCADE"), nullable=False
    )
    document_revision_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document_revision.id", ondelete="CASCADE"), nullable=False
    )
    asset_type: Mapped[str] = mapped_column(
        String(40), nullable=False, default="pomi_watermarked_display"
    )
    watermark_version: Mapped[str] = mapped_column(String(40), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="processing")
    storage_path: Mapped[str | None] = mapped_column(String(500))
    file_hash: Mapped[str | None] = mapped_column(String(64))
    file_size_bytes: Mapped[int | None] = mapped_column(Integer)
    mime_type: Mapped[str | None] = mapped_column(String(64))
    pixel_width: Mapped[int | None] = mapped_column(Integer)
    pixel_height: Mapped[int | None] = mapped_column(Integer)
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    failure_code: Mapped[str | None] = mapped_column(String(80))
    failure_message: Mapped[str | None] = mapped_column(String(500))
    generated_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )
