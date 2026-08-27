"""Patient statements and immutable report provenance foundations."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import JSON, CheckConstraint, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from pomi_backend.db.base import Base
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.db.types import UTCDateTime


class PatientNote(Base):
    __tablename__ = "patient_note"
    __table_args__ = (
        CheckConstraint(
            "status IN ('draft', 'confirmed', 'skipped', 'consumed')",
            name="patient_note_status",
        ),
        Index("ix_patient_note_patient_created", "patient_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    visit_context: Mapped[str | None] = mapped_column(String(200))
    original_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    confirmed_text: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
    confirmed_by_uid: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT")
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    source_note_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("patient_note.id", ondelete="SET NULL")
    )
    consumed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class ReportSnapshot(Base):
    __tablename__ = "report_snapshot"
    __table_args__ = (
        CheckConstraint(
            "report_status IN ('pending', 'succeeded', 'failed')",
            name="report_snapshot_status",
        ),
        CheckConstraint(
            "report_status != 'succeeded' OR "
            "(snapshot_json IS NOT NULL AND snapshot_hash IS NOT NULL "
            "AND report_generated_at IS NOT NULL)",
            name="successful_report_complete",
        ),
        UniqueConstraint("patient_id", "source_digest", name="uq_report_patient_source_digest"),
        Index("ix_report_snapshot_patient_generated", "patient_id", "report_generated_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="RESTRICT"), nullable=False
    )
    patient_note_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("patient_note.id", ondelete="RESTRICT")
    )
    previous_report_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("report_snapshot.id", ondelete="SET NULL")
    )
    report_status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    snapshot_json: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    date_source_json: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    freshness_result_json: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    source_digest: Mapped[str] = mapped_column(String(64), nullable=False)
    snapshot_hash: Mapped[str | None] = mapped_column(String(64))
    generated_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    report_generated_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    failure_reason: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class ReportSource(Base):
    __tablename__ = "report_source"
    __table_args__ = (
        CheckConstraint(
            "source_type IN ('patient_profile', 'patient_note', 'medication', "
            "'medication_event', 'medication_daily', 'menstrual_cycle', "
            "'weight_record', 'lab_observation', 'medical_order', "
            "'imaging_report', 'outpatient_record', 'rule_execution')",
            name="report_source_type",
        ),
        CheckConstraint(
            "origin_kind IN ('medical_document', 'patient_manual', 'system_record', "
            "'rule_execution')",
            name="report_source_origin_kind",
        ),
        CheckConstraint(
            "(origin_kind = 'medical_document' AND document_id IS NOT NULL "
            "AND document_revision_id IS NOT NULL) OR "
            "(origin_kind != 'medical_document' AND document_id IS NULL "
            "AND document_revision_id IS NULL)",
            name="report_source_document_identity",
        ),
        CheckConstraint(
            "(origin_kind = 'rule_execution' AND rule_execution_id IS NOT NULL) OR "
            "(origin_kind != 'rule_execution' AND rule_execution_id IS NULL)",
            name="report_source_rule_identity",
        ),
        UniqueConstraint(
            "report_id", "source_type", "source_record_id", name="uq_report_source_record"
        ),
        Index("ix_report_source_document_revision", "document_id", "document_revision_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    report_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("report_snapshot.id", ondelete="CASCADE"), nullable=False
    )
    source_type: Mapped[str] = mapped_column(String(32), nullable=False)
    source_record_id: Mapped[str] = mapped_column(String(36), nullable=False)
    origin_kind: Mapped[str] = mapped_column(String(24), nullable=False)
    document_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="RESTRICT")
    )
    document_revision_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("document_revision.id", ondelete="RESTRICT")
    )
    rule_execution_id: Mapped[str | None] = mapped_column(String(36))
    included_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
