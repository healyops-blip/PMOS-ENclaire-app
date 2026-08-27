"""Confirmed imaging text and outpatient record models."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from sqlalchemy import JSON, Date, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from pomi_backend.db.base import Base
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.db.types import UTCDateTime


class ImagingReport(Base):
    __tablename__ = "imaging_report"
    __table_args__ = (
        UniqueConstraint("ocr_result_id", name="uq_imaging_report_ocr_result"),
        Index("ix_imaging_report_patient_examined", "patient_id", "examination_date"),
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
    facility: Mapped[str | None] = mapped_column(String(200))
    examination_name: Mapped[str | None] = mapped_column(String(200))
    body_part: Mapped[str | None] = mapped_column(String(200))
    modality: Mapped[str | None] = mapped_column(String(100))
    examination_date: Mapped[date | None] = mapped_column(Date)
    report_date: Mapped[date | None] = mapped_column(Date)
    findings_text: Mapped[str] = mapped_column(Text, nullable=False)
    conclusion_text: Mapped[str] = mapped_column(Text, nullable=False)
    confirmed_payload: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    confirmed_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    confirmed_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class OutpatientRecord(Base):
    __tablename__ = "outpatient_record"
    __table_args__ = (
        UniqueConstraint("ocr_result_id", name="uq_outpatient_record_ocr_result"),
        Index("ix_outpatient_record_patient_visit", "patient_id", "visit_date"),
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
    facility: Mapped[str | None] = mapped_column(String(200))
    department: Mapped[str | None] = mapped_column(String(200))
    doctor_name: Mapped[str | None] = mapped_column(String(100))
    visit_date: Mapped[date] = mapped_column(Date, nullable=False)
    chief_complaint: Mapped[str | None] = mapped_column(Text)
    diagnosis_summary: Mapped[str] = mapped_column(Text, nullable=False)
    treatment_plan: Mapped[str | None] = mapped_column(Text)
    medical_advice: Mapped[str] = mapped_column(Text, nullable=False)
    confirmed_payload: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    confirmed_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    confirmed_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
