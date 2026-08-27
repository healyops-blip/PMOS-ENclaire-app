"""Patient profile and daily health-record persistence models."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import (
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
from pomi_backend.db.types import UTCDateTime


def new_uuid() -> str:
    return str(uuid.uuid4())


class PatientProfile(Base):
    __tablename__ = "patient_profile"
    __table_args__ = (
        CheckConstraint(
            "gender IN ('female', 'male', 'other', 'prefer_not_to_say')",
            name="patient_profile_gender",
        ),
        CheckConstraint("onboarding_step BETWEEN 0 AND 4", name="patient_profile_step"),
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
    height_cm: Mapped[float | None] = mapped_column(Float)
    diagnosis_year: Mapped[int | None] = mapped_column(Integer)
    primary_condition: Mapped[str | None] = mapped_column(String(32), default="pcos")
    usual_cycle_length_days: Mapped[int | None] = mapped_column(Integer)
    next_visit_date: Mapped[date | None] = mapped_column(Date)
    health_goal: Mapped[str | None] = mapped_column(String(500))
    onboarding_step: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    external_ocr_notice_version: Mapped[str | None] = mapped_column(String(32))
    external_ocr_notice_accepted_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class Medication(Base):
    __tablename__ = "medication"
    __table_args__ = (
        CheckConstraint(
            "current_status IN ('active', 'stopped', 'unknown')",
            name="medication_status",
        ),
        UniqueConstraint("patient_id", "idempotency_key", name="uq_medication_idempotency"),
        Index("ix_medication_patient_status", "patient_id", "current_status"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    drug_name: Mapped[str] = mapped_column(String(200), nullable=False)
    normalized_drug_name: Mapped[str] = mapped_column(String(200), nullable=False)
    specification: Mapped[str | None] = mapped_column(String(200))
    dosage_text: Mapped[str | None] = mapped_column(String(200))
    dosage_value: Mapped[float | None] = mapped_column(Float)
    dosage_unit: Mapped[str | None] = mapped_column(String(32))
    frequency: Mapped[str | None] = mapped_column(String(200))
    route: Mapped[str | None] = mapped_column(String(80))
    start_date: Mapped[date | None] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date)
    current_status: Mapped[str] = mapped_column(String(16), nullable=False, default="active")
    source_type: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
    source_document_id: Mapped[str | None] = mapped_column(String(36))
    idempotency_key: Mapped[str | None] = mapped_column(String(128))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class MedicationEvent(Base):
    __tablename__ = "medication_event"
    __table_args__ = (
        CheckConstraint(
            "event_type IN ('started', 'adjusted', 'continued', 'stopped')",
            name="medication_event_type",
        ),
        CheckConstraint(
            "stop_source IS NULL OR stop_source IN "
            "('written_order', 'verbal_doctor', 'patient_self', 'other')",
            name="medication_event_stop_source",
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
    old_instruction_json: Mapped[str | None] = mapped_column(Text)
    new_instruction_json: Mapped[str | None] = mapped_column(Text)
    source_document_id: Mapped[str | None] = mapped_column(String(36))
    confirmed_by_uid: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="SET NULL")
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    stop_source: Mapped[str | None] = mapped_column(String(32))
    note: Mapped[str | None] = mapped_column(String(500))


class MedicationDaily(Base):
    __tablename__ = "medication_daily"
    __table_args__ = (
        CheckConstraint(
            "intake_status IN ('taken', 'missed', 'unrecorded')",
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
    actual_dosage: Mapped[float | None] = mapped_column(Float)
    actual_dosage_unit: Mapped[str | None] = mapped_column(String(32))
    note: Mapped[str | None] = mapped_column(String(500))
    recorded_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    recorded_by_uid: Mapped[str] = mapped_column(
        String(36), ForeignKey("user_account.uid", ondelete="CASCADE"), nullable=False
    )


class MenstrualCycle(Base):
    __tablename__ = "menstrual_cycle"
    __table_args__ = (
        CheckConstraint(
            "flow_level IS NULL OR flow_level IN ('light', 'medium', 'heavy', 'unknown')",
            name="menstrual_cycle_flow",
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
    note: Mapped[str | None] = mapped_column(String(500))
    source_type: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )


class WeightRecord(Base):
    __tablename__ = "weight_record"
    __table_args__ = (
        CheckConstraint("weight_kg >= 20 AND weight_kg <= 350", name="weight_record_range"),
        UniqueConstraint("patient_id", "record_date", name="uq_weight_record_patient_date"),
        Index("ix_weight_record_patient_date", "patient_id", "record_date"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    patient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("patient_profile.patient_id", ondelete="CASCADE"), nullable=False
    )
    measured_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
    record_date: Mapped[date] = mapped_column(Date, nullable=False)
    weight_kg: Mapped[float] = mapped_column(Float, nullable=False)
    source_type: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
    note: Mapped[str | None] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )
