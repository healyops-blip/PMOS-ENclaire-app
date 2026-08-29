"""Confirmed medical orders and deterministic medication reconciliations."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Date,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from pomi_backend.db.base import Base
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.db.types import UTCDateTime


class MedicalOrder(Base):
    __tablename__ = "medical_order"
    __table_args__ = (
        UniqueConstraint("ocr_result_id", "medication_index", name="uq_medical_order_result_item"),
        CheckConstraint(
            "length(trim(raw_order_text)) > 0", name="ck_medical_order_source_nonblank"
        ),
        CheckConstraint("length(trim(drug_name)) > 0", name="ck_medical_order_drug_nonblank"),
        CheckConstraint("dosage_value > 0", name="ck_medical_order_dosage_positive"),
        CheckConstraint("length(trim(dosage_unit)) > 0", name="ck_medical_order_unit_nonblank"),
        CheckConstraint("length(trim(frequency)) > 0", name="ck_medical_order_frequency_nonblank"),
        Index("ix_medical_order_patient_confirmed", "patient_id", "confirmed_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="RESTRICT"), nullable=False
    )
    document_revision_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document_revision.id", ondelete="RESTRICT"), nullable=False
    )
    ocr_result_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_result.id", ondelete="RESTRICT"), nullable=False
    )
    ocr_task_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_task.id", ondelete="RESTRICT"), nullable=False
    )
    medication_index: Mapped[int] = mapped_column(Integer, nullable=False)
    raw_order_text: Mapped[str] = mapped_column(Text, nullable=False)
    drug_name: Mapped[str] = mapped_column(String(200), nullable=False)
    standard_drug_id: Mapped[str | None] = mapped_column(String(80))
    specification: Mapped[str | None] = mapped_column(String(200))
    dosage_value: Mapped[Decimal] = mapped_column(Numeric(8, 3), nullable=False)
    dosage_unit: Mapped[str] = mapped_column(String(32), nullable=False)
    frequency: Mapped[str] = mapped_column(String(200), nullable=False)
    course: Mapped[str | None] = mapped_column(String(200))
    route: Mapped[str | None] = mapped_column(String(80))
    instructions: Mapped[str | None] = mapped_column(Text)
    order_date: Mapped[date] = mapped_column(Date, nullable=False)
    explicitly_stopped: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    review_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    original_item_data: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    confirmed_item_data: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    confirmed_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    confirmed_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class MedicationReconciliation(Base):
    __tablename__ = "medication_reconciliation"
    __table_args__ = (
        CheckConstraint(
            "status IN ('draft', 'executing', 'executed')",
            name="medication_reconciliation_status",
        ),
        UniqueConstraint("patient_id", "ocr_task_id", name="uq_reconciliation_patient_task"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    ocr_task_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_task.id", ondelete="RESTRICT"), nullable=False
    )
    rule_version: Mapped[str] = mapped_column(String(40), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
    created_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    executed_by_uid: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT")
    )
    executed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    execution_payload: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class MedicationReconciliationItem(Base):
    __tablename__ = "medication_reconciliation_item"
    __table_args__ = (
        CheckConstraint(
            "suggestion IN ('unchanged', 'adjusted', 'added', "
            "'stopped', 'uncertain', 'manual_review')",
            name="medication_reconciliation_item_suggestion",
        ),
        CheckConstraint(
            "user_decision IS NULL OR user_decision IN ('accept', 'keep_current', 'reject')",
            name="medication_reconciliation_item_decision",
        ),
        CheckConstraint(
            "old_medication_id IS NOT NULL OR new_medical_order_id IS NOT NULL",
            name="ck_reconciliation_item_has_source",
        ),
        UniqueConstraint("reconciliation_id", "position", name="uq_reconciliation_item_position"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    reconciliation_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("medication_reconciliation.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    old_medication_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("medication.id", ondelete="RESTRICT")
    )
    new_medical_order_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("medical_order.id", ondelete="RESTRICT")
    )
    match_basis: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    suggestion: Mapped[str] = mapped_column(String(24), nullable=False)
    user_decision: Mapped[str | None] = mapped_column(String(24))
    decision_note: Mapped[str | None] = mapped_column(String(500))
    stop_date: Mapped[date | None] = mapped_column(Date)
    stop_source: Mapped[str | None] = mapped_column(String(80))
    execution_result: Mapped[dict[str, Any] | None] = mapped_column(JSON)
