"""Patient ownership and foundational health-record persistence models."""

from __future__ import annotations

import uuid
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
from pomi_backend.db.types import UTCDateTime


def new_uuid() -> str:
    return str(uuid.uuid4())


class PatientProfile(Base):
    """One patient profile owned by one authenticated account."""

    __tablename__ = "patient_profile"
    __table_args__ = (
        CheckConstraint(
            "gender IS NULL OR gender IN ('female', 'male', 'other', 'prefer_not_to_say')",
            name="patient_profile_gender",
        ),
    )

    patient_id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    account_uid: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("user_account.uid", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    nickname: Mapped[str | None] = mapped_column(String(80))
    birth_date: Mapped[date | None] = mapped_column(Date)
    gender: Mapped[str | None] = mapped_column(String(24))
    height_cm: Mapped[Decimal | None] = mapped_column(Numeric(4, 1))
    diagnosis_year: Mapped[int | None] = mapped_column(Integer)
    primary_condition: Mapped[str | None] = mapped_column(String(80))
    next_visit_date: Mapped[date | None] = mapped_column(Date)
    health_goal: Mapped[str | None] = mapped_column(String(500))
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    onboarding_completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class Medication(Base):
    __tablename__ = "medication"
    __table_args__ = (
        CheckConstraint(
            "source_category IN ('prescribed', 'supplement', 'other_long_term')",
            name="medication_source_category",
        ),
        CheckConstraint(
            "status IN ('active', 'paused', 'stopped')",
            name="medication_status",
        ),
        CheckConstraint(
            "end_date IS NULL OR start_date IS NULL OR end_date >= start_date",
            name="medication_date_order",
        ),
        Index("ix_medication_patient_status", "patient_id", "status"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    drug_name: Mapped[str] = mapped_column(String(200), nullable=False)
    source_category: Mapped[str] = mapped_column(String(32), nullable=False)
    specification: Mapped[str | None] = mapped_column(String(200))
    dosage_value: Mapped[Decimal | None] = mapped_column(Numeric(8, 3))
    dosage_unit: Mapped[str | None] = mapped_column(String(32))
    frequency: Mapped[str | None] = mapped_column(String(200))
    route: Mapped[str | None] = mapped_column(String(80))
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="active")
    start_date: Mapped[date | None] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date)
    replaces_medication_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("medication.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class MedicationEvent(Base):
    __tablename__ = "medication_event"
    __table_args__ = (
        CheckConstraint(
            "event_type IN ('created', 'adjusted', 'paused', 'resumed', 'stopped')",
            name="medication_event_type",
        ),
        Index("ix_medication_event_medication_date", "medication_id", "event_date"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    medication_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("medication.id", ondelete="CASCADE"), nullable=False
    )
    event_type: Mapped[str] = mapped_column(String(16), nullable=False)
    event_date: Mapped[date] = mapped_column(Date, nullable=False)
    old_instruction: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    new_instruction: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    source_type: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
    source_document_id: Mapped[str | None] = mapped_column(String(36))
    acted_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    note: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class MedicationDaily(Base):
    __tablename__ = "medication_daily"
    __table_args__ = (
        CheckConstraint(
            "intake_status IN ('taken', 'missed')",
            name="medication_daily_status",
        ),
        UniqueConstraint("medication_id", "record_date", name="uq_medication_daily_date"),
        Index("ix_medication_daily_patient_date", "patient_id", "record_date"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    medication_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("medication.id", ondelete="CASCADE"), nullable=False
    )
    record_date: Mapped[date] = mapped_column(Date, nullable=False)
    intake_status: Mapped[str] = mapped_column(String(16), nullable=False)
    recorded_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="RESTRICT"), nullable=False
    )
    recorded_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class MenstrualCycle(Base):
    __tablename__ = "menstrual_cycle"
    __table_args__ = (
        CheckConstraint(
            "end_date IS NULL OR end_date >= start_date",
            name="menstrual_cycle_date_order",
        ),
        Index("ix_menstrual_cycle_patient_start", "patient_id", "start_date"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date | None] = mapped_column(Date)
    note: Mapped[str | None] = mapped_column(Text)
    deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class WeightRecord(Base):
    __tablename__ = "weight_record"
    __table_args__ = (
        CheckConstraint("weight_kg >= 20 AND weight_kg <= 300", name="weight_range"),
        UniqueConstraint("patient_id", "record_date", name="uq_weight_patient_date"),
        Index("ix_weight_record_patient_date", "patient_id", "record_date"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    record_date: Mapped[date] = mapped_column(Date, nullable=False)
    weight_kg: Mapped[Decimal] = mapped_column(Numeric(4, 1), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )
