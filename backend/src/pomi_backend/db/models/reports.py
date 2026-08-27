"""Medication reconciliation, deterministic rules, and report persistence."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    DDL,
    JSON,
    CheckConstraint,
    Date,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    event,
)
from sqlalchemy.orm import Mapped, mapped_column

from pomi_backend.db.base import Base
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.db.types import UTCDateTime


class MedicationReconciliation(Base):
    __tablename__ = "medication_reconciliation"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'confirmed', 'cancelled')",
            name="medication_reconciliation_status",
        ),
        UniqueConstraint("created_by_uid", "idempotency_key", name="uq_reconciliation_idempotency"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    source_document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="CASCADE"), nullable=False
    )
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    summary: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    created_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    confirmed_by_uid: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="SET NULL")
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class MedicationReconciliationItem(Base):
    __tablename__ = "medication_reconciliation_item"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    reconciliation_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("medication_reconciliation.id", ondelete="CASCADE"), nullable=False
    )
    existing_medication_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("medication.id", ondelete="SET NULL")
    )
    new_medical_order_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("medical_order.id", ondelete="SET NULL")
    )
    medication_concept_id: Mapped[str | None] = mapped_column(String(100))
    drug_name: Mapped[str] = mapped_column(String(200), nullable=False)
    comparison_type: Mapped[str] = mapped_column(String(32), nullable=False)
    rule_id: Mapped[str | None] = mapped_column(String(36))
    old_instruction: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    new_instruction: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    differences: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    user_decision: Mapped[str | None] = mapped_column(String(32))
    decision_note: Mapped[str | None] = mapped_column(String(500))
    stop_date: Mapped[date | None] = mapped_column(Date)
    stop_source: Mapped[str | None] = mapped_column(String(32))


class DeterministicRule(Base):
    __tablename__ = "deterministic_rule"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    rule_key: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    rule_type: Mapped[str] = mapped_column(String(32), nullable=False)
    rule_name: Mapped[str] = mapped_column(String(200), nullable=False)
    parameters: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
    enabled: Mapped[bool] = mapped_column(nullable=False, default=True)
    updated_by_uid: Mapped[str | None] = mapped_column(String(36))
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class RuleExecution(Base):
    __tablename__ = "rule_execution"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    rule_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("deterministic_rule.id", ondelete="CASCADE"), nullable=False
    )
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    source_type: Mapped[str] = mapped_column(String(64), nullable=False)
    source_id: Mapped[str] = mapped_column(String(36), nullable=False)
    input_digest: Mapped[str] = mapped_column(String(64), nullable=False)
    input: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    output: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    explanation: Mapped[str] = mapped_column(Text, nullable=False)
    executed_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class PatientNote(Base):
    __tablename__ = "patient_note"
    __table_args__ = (
        CheckConstraint(
            "confirmation_status IN ('draft', 'confirmed', 'cancelled')",
            name="patient_note_status",
        ),
        Index("ix_patient_note_patient_created", "patient_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    original_text: Mapped[str] = mapped_column(Text, nullable=False)
    confirmed_text: Mapped[str | None] = mapped_column(Text)
    confirmation_status: Mapped[str] = mapped_column(String(16), nullable=False)
    confirmed_by_uid: Mapped[str | None] = mapped_column(String(36))
    confirmed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class ReportSnapshot(Base):
    __tablename__ = "report_snapshot"
    __table_args__ = (
        CheckConstraint(
            "status IN ('generating', 'succeeded', 'failed')",
            name="report_snapshot_status",
        ),
        UniqueConstraint("generated_by_uid", "idempotency_key", name="uq_report_idempotency"),
        Index("ix_report_snapshot_patient_generated", "patient_id", "generated_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    patient_note_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("patient_note.id", ondelete="SET NULL")
    )
    previous_report_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("report_snapshot.id", ondelete="SET NULL")
    )
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    snapshot: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    data_freshness: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    source_digest: Mapped[str] = mapped_column(String(64), nullable=False)
    snapshot_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    include_sections: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    generated_by_uid: Mapped[str] = mapped_column(String(36), nullable=False)
    generated_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    failure_reason: Mapped[str | None] = mapped_column(String(500))


class ReportSource(Base):
    __tablename__ = "report_source"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    report_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("report_snapshot.id", ondelete="CASCADE"), nullable=False
    )
    source_number: Mapped[int] = mapped_column(Integer, nullable=False)
    source_type: Mapped[str] = mapped_column(String(64), nullable=False)
    source_id: Mapped[str] = mapped_column(String(36), nullable=False)
    document_id: Mapped[str | None] = mapped_column(String(36))
    document_revision_id: Mapped[str | None] = mapped_column(String(36))
    rule_execution_id: Mapped[str | None] = mapped_column(String(36))
    original_value: Mapped[str | None] = mapped_column(Text)
    original_unit: Mapped[str | None] = mapped_column(String(50))
    reference_range_text: Mapped[str | None] = mapped_column(String(200))
    material_date: Mapped[date | None] = mapped_column(Date)
    date_source: Mapped[str] = mapped_column(String(50), nullable=False)
    included_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class ReportFile(Base):
    __tablename__ = "report_file"
    __table_args__ = (
        CheckConstraint(
            "generation_status IN ('pending', 'processing', 'succeeded', 'failed')",
            name="report_file_status",
        ),
        UniqueConstraint("report_id", "file_type", name="uq_report_file_type"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    report_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("report_snapshot.id", ondelete="CASCADE"), nullable=False
    )
    file_type: Mapped[str] = mapped_column(String(16), nullable=False, default="pdf")
    storage_path: Mapped[str | None] = mapped_column(String(500))
    file_hash: Mapped[str | None] = mapped_column(String(64))
    file_size_bytes: Mapped[int | None] = mapped_column(Integer)
    generation_status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    generated_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    failure_reason: Mapped[str | None] = mapped_column(String(500))


event.listen(
    ReportSnapshot.__table__,
    "after_create",
    DDL(
        """
        CREATE TRIGGER IF NOT EXISTS prevent_report_snapshot_update
        BEFORE UPDATE ON report_snapshot
        BEGIN
            SELECT RAISE(ABORT, 'report snapshots are immutable');
        END
        """
    ).execute_if(dialect="sqlite"),
)
