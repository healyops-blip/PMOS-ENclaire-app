"""Confirmed, traceable laboratory observations."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    JSON,
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


class LabObservation(Base):
    """A user-confirmed numeric laboratory item; OCR drafts never enter this table."""

    __tablename__ = "lab_observation"
    __table_args__ = (
        CheckConstraint(
            "mapping_status IN ('mapped', 'needs_manual_review')",
            name="lab_observation_mapping_status",
        ),
        CheckConstraint(
            "abnormal_status IN ('low', 'normal', 'high', 'unknown')",
            name="lab_observation_abnormal_status",
        ),
        CheckConstraint(
            "trend_date_source IS NULL OR "
            "trend_date_source IN ('sample_date', 'exam_date', 'report_date', 'visit_date')",
            name="lab_observation_trend_date_source",
        ),
        UniqueConstraint("ocr_result_id", "item_index", name="uq_lab_observation_result_item"),
        Index(
            "ix_lab_observation_patient_metric_date",
            "patient_id",
            "standard_metric_id",
            "trend_date",
        ),
        Index("ix_lab_observation_document_revision", "document_id", "document_revision_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    visit_id: Mapped[str | None] = mapped_column(String(100))
    document_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document.id", ondelete="RESTRICT"), nullable=False
    )
    document_revision_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("document_revision.id", ondelete="RESTRICT"), nullable=False
    )
    ocr_result_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ocr_result.id", ondelete="RESTRICT"), nullable=False
    )
    item_index: Mapped[int] = mapped_column(Integer, nullable=False)
    original_item_name: Mapped[str] = mapped_column(String(200), nullable=False)
    standard_metric_id: Mapped[str | None] = mapped_column(String(80))
    mapping_status: Mapped[str] = mapped_column(String(24), nullable=False)
    raw_value: Mapped[str] = mapped_column(String(100), nullable=False)
    numeric_value: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    original_unit: Mapped[str] = mapped_column(String(40), nullable=False)
    standard_unit: Mapped[str] = mapped_column(String(40), nullable=False)
    reference_range_raw: Mapped[str | None] = mapped_column(String(120))
    reference_lower: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    reference_upper: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    abnormal_status: Mapped[str] = mapped_column(String(16), nullable=False)
    sample_date: Mapped[date | None] = mapped_column(Date)
    exam_date: Mapped[date | None] = mapped_column(Date)
    report_date: Mapped[date | None] = mapped_column(Date)
    visit_date: Mapped[date | None] = mapped_column(Date)
    trend_date: Mapped[date | None] = mapped_column(Date)
    trend_date_source: Mapped[str | None] = mapped_column(String(20))
    original_item_data: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    confirmed_item_data: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    confirmed_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    confirmed_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    note: Mapped[str | None] = mapped_column(Text)
