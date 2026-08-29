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
    ForeignKeyConstraint,
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
        CheckConstraint(
            "usual_cycle_min_days IS NULL OR usual_cycle_max_days IS NULL "
            "OR usual_cycle_min_days <= usual_cycle_max_days",
            name="patient_profile_cycle_range",
        ),
        CheckConstraint(
            "period_duration_days IS NULL OR period_duration_days BETWEEN 1 AND 14",
            name="patient_profile_period_duration",
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
    birth_year: Mapped[int | None] = mapped_column(Integer)
    birth_date: Mapped[date | None] = mapped_column(Date)
    gender: Mapped[str | None] = mapped_column(String(24))
    height_cm: Mapped[Decimal | None] = mapped_column(Numeric(4, 1))
    diagnosis_year: Mapped[int | None] = mapped_column(Integer)
    usual_cycle_min_days: Mapped[int | None] = mapped_column(Integer)
    usual_cycle_max_days: Mapped[int | None] = mapped_column(Integer)
    period_duration_days: Mapped[int | None] = mapped_column(Integer)
    primary_condition: Mapped[str | None] = mapped_column(String(80))
    next_visit_date: Mapped[date | None] = mapped_column(Date)
    health_goal: Mapped[str | None] = mapped_column(String(500))
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    onboarding_completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class OnboardingDraft(Base):
    """Durable, resumable onboarding state kept separate from the formal profile."""

    __tablename__ = "onboarding_draft"
    __table_args__ = (
        CheckConstraint(
            "current_step IN ('basic', 'cycle', 'medications', 'complete')",
            name="onboarding_draft_current_step",
        ),
        UniqueConstraint("account_uid", name="uq_onboarding_draft_account_uid"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    account_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="CASCADE"), nullable=False
    )
    current_step: Mapped[str] = mapped_column(String(16), nullable=False, default="basic")
    basic_data: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    cycle_data: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    medications_data: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
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
        ForeignKeyConstraint(
            ["patient_id", "replaces_medication_id"],
            ["medication.patient_id", "medication.id"],
            name="fk_medication_replacement_same_patient",
            ondelete="RESTRICT",
        ),
        UniqueConstraint("patient_id", "id", name="uq_medication_patient_id"),
        Index("ix_medication_patient_status", "patient_id", "status"),
        UniqueConstraint("patient_id", "idempotency_key", name="uq_medication_patient_idempotency"),
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
    standard_drug_id: Mapped[str | None] = mapped_column(String(80))
    frequency: Mapped[str | None] = mapped_column(String(200))
    route: Mapped[str | None] = mapped_column(String(80))
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="active")
    start_date: Mapped[date | None] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date)
    replaces_medication_id: Mapped[str | None] = mapped_column(String(36))
    idempotency_key: Mapped[str | None] = mapped_column(String(128))
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
        ForeignKeyConstraint(
            ["patient_id", "medication_id"],
            ["medication.patient_id", "medication.id"],
            name="fk_medication_event_medication_same_patient",
            ondelete="CASCADE",
        ),
        Index("ix_medication_event_medication_date", "medication_id", "event_date"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    medication_id: Mapped[str] = mapped_column(String(36), nullable=False)
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
    stop_source: Mapped[str | None] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)


class MedicationDaily(Base):
    __tablename__ = "medication_daily"
    __table_args__ = (
        CheckConstraint(
            "intake_status IN ('taken', 'missed')",
            name="medication_daily_status",
        ),
        ForeignKeyConstraint(
            ["patient_id", "medication_id"],
            ["medication.patient_id", "medication.id"],
            name="fk_medication_daily_medication_same_patient",
            ondelete="CASCADE",
        ),
        UniqueConstraint("medication_id", "record_date", name="uq_medication_daily_date"),
        Index("ix_medication_daily_patient_date", "patient_id", "record_date"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    medication_id: Mapped[str] = mapped_column(String(36), nullable=False)
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
        CheckConstraint(
            "flow_level IS NULL OR flow_level IN ('light', 'medium', 'heavy', 'unknown')",
            name="menstrual_cycle_flow_level",
        ),
        CheckConstraint(
            "source_type IN ('manual', 'imported')",
            name="menstrual_cycle_source_type",
        ),
        Index("ix_menstrual_cycle_patient_start", "patient_id", "start_date"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date | None] = mapped_column(Date)
    flow_level: Mapped[str | None] = mapped_column(String(16))
    note: Mapped[str | None] = mapped_column(Text)
    source_type: Mapped[str] = mapped_column(String(16), nullable=False, default="manual")
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
