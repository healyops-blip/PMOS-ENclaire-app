"""Auditable asynchronous OCR task, result, and field models."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import (
    JSON,
    CheckConstraint,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from pomi_backend.db.base import Base
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.db.types import UTCDateTime


class OCRTask(Base):
    __tablename__ = "ocr_task"
    __table_args__ = (
        CheckConstraint(
            "status IN ('queued', 'processing', 'pending_confirmation', 'confirmed', "
            "'failed', 'timed_out')",
            name="ocr_task_status",
        ),
        CheckConstraint(
            "material_type IN ('lab_report', 'medical_order', 'imaging_text_report', "
            "'outpatient_record')",
            name="ocr_task_material_type",
        ),
        UniqueConstraint("deduplication_key", name="uq_ocr_task_deduplication_key"),
        UniqueConstraint("parent_task_id", name="uq_ocr_task_parent_retry"),
        Index("ix_ocr_task_claim", "status", "available_at", "lease_expires_at"),
        Index("ix_ocr_task_patient_created", "patient_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    requested_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="RESTRICT"), nullable=False
    )
    document_revision_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document_revision.id", ondelete="RESTRICT"), nullable=False
    )
    material_type: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="queued")
    model_name: Mapped[str] = mapped_column(String(100), nullable=False)
    prompt_version: Mapped[str] = mapped_column(String(40), nullable=False)
    schema_version: Mapped[str] = mapped_column(String(40), nullable=False)
    attempt_number: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    parent_task_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("ocr_task.id", ondelete="SET NULL")
    )
    provider_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    attempt_history: Mapped[list[dict[str, Any]]] = mapped_column(
        JSON, nullable=False, default=list
    )
    lease_owner: Mapped[str | None] = mapped_column(String(100))
    lease_expires_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    available_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    provider_call_started_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    started_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    finished_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    duration_ms: Mapped[int | None] = mapped_column(Integer)
    error_category: Mapped[str | None] = mapped_column(String(40))
    error_code: Mapped[str | None] = mapped_column(String(80))
    error_message: Mapped[str | None] = mapped_column(String(500))
    result_source: Mapped[str | None] = mapped_column(String(80))
    deduplication_key: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class OCRResult(Base):
    __tablename__ = "ocr_result"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    task_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_task.id", ondelete="CASCADE"), nullable=False, unique=True
    )
    raw_response: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    validated_draft: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    user_modified_data: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    confirmed_data: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class OCRFieldResult(Base):
    __tablename__ = "ocr_field_result"
    __table_args__ = (
        CheckConstraint(
            "confirmation_status IN ('pending', 'accepted', 'corrected', 'rejected')",
            name="ocr_field_confirmation_status",
        ),
        UniqueConstraint("result_id", "field_path", name="uq_ocr_field_result_path"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    result_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_result.id", ondelete="CASCADE"), nullable=False
    )
    field_path: Mapped[str] = mapped_column(String(300), nullable=False)
    source_text: Mapped[str | None] = mapped_column(Text)
    parsed_value: Mapped[Any] = mapped_column(JSON, nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False)
    uncertainty_reason: Mapped[str | None] = mapped_column(String(500))
    source_region: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    user_value: Mapped[Any | None] = mapped_column(JSON)
    confirmation_status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )
