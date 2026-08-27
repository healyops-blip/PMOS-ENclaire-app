"""Medical document, OCR task, and confirmed-record persistence models."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Date,
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


class Encounter(Base):
    __tablename__ = "encounter"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    hospital_name: Mapped[str | None] = mapped_column(String(200))
    department_name: Mapped[str | None] = mapped_column(String(200))
    doctor_name: Mapped[str | None] = mapped_column(String(100))
    visit_date: Mapped[date | None] = mapped_column(Date)
    encounter_type: Mapped[str | None] = mapped_column(String(50))
    source_type: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class Document(Base):
    __tablename__ = "document"
    __table_args__ = (
        CheckConstraint(
            "document_type IN "
            "('lab_report', 'medical_order', 'imaging_text_report', 'outpatient_record')",
            name="document_type",
        ),
        UniqueConstraint(
            "uploaded_by_uid", "idempotency_key", name="uq_document_upload_idempotency"
        ),
        CheckConstraint(
            "upload_status IN ('uploaded', 'processing', 'ready', 'failed', 'deleted')",
            name="document_upload_status",
        ),
        Index("ix_document_patient_type_uploaded", "patient_id", "document_type", "uploaded_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    encounter_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("encounter.id", ondelete="SET NULL")
    )
    document_type: Mapped[str] = mapped_column(String(32), nullable=False)
    original_file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False)
    file_size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    pixel_count: Mapped[int | None] = mapped_column(Integer)
    page_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    file_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    upload_status: Mapped[str] = mapped_column(String(16), nullable=False, default="uploaded")
    current_revision_id: Mapped[str] = mapped_column(String(36), nullable=False)
    uploaded_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="CASCADE"), nullable=False
    )
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    uploaded_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
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
    replaced_revision_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("document_revision.id", ondelete="SET NULL")
    )
    replacement_reason: Mapped[str | None] = mapped_column(String(500))
    idempotency_key: Mapped[str | None] = mapped_column(String(128))
    is_current: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class OcrTask(Base):
    __tablename__ = "ocr_task"
    __table_args__ = (
        CheckConstraint(
            "task_status IN "
            "('pending', 'processing', 'succeeded', 'failed', 'timeout', 'fallback', 'confirmed')",
            name="ocr_task_status",
        ),
        UniqueConstraint("created_by_uid", "idempotency_key", name="uq_ocr_task_idempotency"),
        Index("ix_ocr_task_queue", "task_status", "queued_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="CASCADE"), nullable=False
    )
    document_revision_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document_revision.id", ondelete="CASCADE"), nullable=False
    )
    document_type: Mapped[str] = mapped_column(String(32), nullable=False)
    task_status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    model_name: Mapped[str] = mapped_column(String(100), nullable=False)
    prompt_key: Mapped[str] = mapped_column(String(100), nullable=False)
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    max_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    lease_owner: Mapped[str | None] = mapped_column(String(200))
    lease_expires_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    queued_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    started_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    finished_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    processing_ms: Mapped[int | None] = mapped_column(Integer)
    error_code: Mapped[str | None] = mapped_column(String(64))
    error_message: Mapped[str | None] = mapped_column(String(500))
    result_source: Mapped[str | None] = mapped_column(String(32))
    progress: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    created_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="CASCADE"), nullable=False
    )


class OcrResult(Base):
    __tablename__ = "ocr_result"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    ocr_task_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_task.id", ondelete="CASCADE"), nullable=False, unique=True
    )
    raw_response_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    parsed_result_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    validation_status: Mapped[str] = mapped_column(String(32), nullable=False)
    validation_errors_json: Mapped[list[dict[str, Any]]] = mapped_column(
        JSON, nullable=False, default=list
    )
    confirmed_result_json: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    confirmed_by_uid: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="SET NULL")
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    critical_error: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class OcrFieldResult(Base):
    __tablename__ = "ocr_field_result"
    __table_args__ = (
        UniqueConstraint("ocr_result_id", "field_path", name="uq_ocr_field_result_path"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    ocr_result_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_result.id", ondelete="CASCADE"), nullable=False
    )
    field_path: Mapped[str] = mapped_column(String(500), nullable=False)
    raw_text: Mapped[str | None] = mapped_column(Text)
    parsed_value: Mapped[Any | None] = mapped_column(JSON)
    confidence: Mapped[float | None] = mapped_column(Float)
    uncertainty_reason: Mapped[str | None] = mapped_column(String(500))
    source_region: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    user_value: Mapped[Any | None] = mapped_column(JSON)
    confirmation_status: Mapped[str] = mapped_column(String(24), nullable=False, default="pending")
    confirmed_by_uid: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="SET NULL")
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class LabObservation(Base):
    __tablename__ = "lab_observation"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="CASCADE"), nullable=False
    )
    ocr_result_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_result.id", ondelete="CASCADE"), nullable=False
    )
    item_name: Mapped[str] = mapped_column(String(200), nullable=False)
    item_code: Mapped[str | None] = mapped_column(String(100))
    raw_value: Mapped[str] = mapped_column(String(200), nullable=False)
    numeric_value: Mapped[float | None] = mapped_column(Float)
    raw_unit: Mapped[str | None] = mapped_column(String(50))
    normalized_unit: Mapped[str | None] = mapped_column(String(50))
    reference_range_text: Mapped[str | None] = mapped_column(String(200))
    reference_low: Mapped[float | None] = mapped_column(Float)
    reference_high: Mapped[float | None] = mapped_column(Float)
    abnormal_status: Mapped[str | None] = mapped_column(String(16))
    sample_date: Mapped[date | None] = mapped_column(Date)
    report_date: Mapped[date | None] = mapped_column(Date)
    confirmed_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid"), nullable=False
    )
    confirmed_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)


class MedicalOrder(Base):
    __tablename__ = "medical_order"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="CASCADE"), nullable=False
    )
    ocr_result_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_result.id", ondelete="CASCADE"), nullable=False
    )
    source_text: Mapped[str] = mapped_column(Text, nullable=False)
    drug_name: Mapped[str] = mapped_column(String(200), nullable=False)
    normalized_drug_name: Mapped[str] = mapped_column(String(200), nullable=False)
    specification: Mapped[str | None] = mapped_column(String(200))
    dosage_text: Mapped[str | None] = mapped_column(String(300))
    dosage_value: Mapped[float | None] = mapped_column(Float)
    dosage_unit: Mapped[str | None] = mapped_column(String(50))
    frequency: Mapped[str | None] = mapped_column(String(100))
    duration: Mapped[str | None] = mapped_column(String(100))
    route: Mapped[str | None] = mapped_column(String(100))
    instruction: Mapped[str | None] = mapped_column(Text)
    prescribed_at: Mapped[date | None] = mapped_column(Date)
    confirmed_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid"), nullable=False
    )
    confirmed_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)


class ImagingReport(Base):
    __tablename__ = "imaging_report"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="CASCADE"), nullable=False
    )
    ocr_result_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_result.id", ondelete="CASCADE"), nullable=False
    )
    examination_name: Mapped[str | None] = mapped_column(String(200))
    body_part: Mapped[str | None] = mapped_column(String(200))
    examination_method: Mapped[str | None] = mapped_column(String(200))
    findings_text: Mapped[str] = mapped_column(Text, nullable=False)
    conclusion_text: Mapped[str] = mapped_column(Text, nullable=False)
    examined_at: Mapped[date | None] = mapped_column(Date)
    reported_at: Mapped[date | None] = mapped_column(Date)
    confirmed_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid"), nullable=False
    )
    confirmed_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)


class OutpatientRecord(Base):
    __tablename__ = "outpatient_record"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="CASCADE"), nullable=False
    )
    ocr_result_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_result.id", ondelete="CASCADE"), nullable=False
    )
    hospital_name: Mapped[str | None] = mapped_column(String(200))
    department_name: Mapped[str | None] = mapped_column(String(200))
    doctor_name: Mapped[str | None] = mapped_column(String(100))
    visit_date: Mapped[date] = mapped_column(Date, nullable=False)
    chief_complaint: Mapped[str] = mapped_column(Text, nullable=False)
    diagnosis_summary: Mapped[str] = mapped_column(Text, nullable=False)
    treatment_plan: Mapped[str | None] = mapped_column(Text)
    medical_advice: Mapped[str | None] = mapped_column(Text)
    confirmed_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid"), nullable=False
    )
    confirmed_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
