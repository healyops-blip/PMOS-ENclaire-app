"""Health check, patient, tracking, and dashboard API schemas."""

from __future__ import annotations

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"


class StrictRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")


class PatientProfileUpdate(StrictRequest):
    nickname: str | None = Field(default=None, max_length=80)
    birth_date: date | None = None
    gender: Literal["female", "male", "other", "prefer_not_to_say"] | None = None
    height_cm: float | None = Field(default=None, ge=80, le=250)
    diagnosis_year: int | None = Field(default=None, ge=1900)
    primary_condition: str | None = Field(default=None, max_length=80)
    usual_cycle_length_days: int | None = Field(default=None, ge=15, le=120)
    last_menstrual_start_date: date | None = None
    next_visit_date: date | None = None
    health_goal: str | None = Field(default=None, max_length=500)
    accept_external_ocr_notice: bool | None = None
    complete_onboarding: bool | None = None
    updated_at: datetime | None = None

    @model_validator(mode="after")
    def require_at_least_one_field(self) -> PatientProfileUpdate:
        if not self.model_fields_set:
            raise ValueError("at least one field is required")
        return self


class MedicationInstruction(StrictRequest):
    drug_name: str | None = Field(default=None, min_length=1, max_length=200)
    specification: str | None = Field(default=None, max_length=200)
    dosage_text: str | None = Field(default=None, max_length=300)
    dosage_value: float | None = Field(default=None, ge=0)
    dosage_unit: str | None = Field(default=None, max_length=50)
    frequency: str | None = Field(default=None, max_length=100)
    route: str | None = Field(default=None, max_length=100)


class MedicationCreate(MedicationInstruction):
    drug_name: str = Field(min_length=1, max_length=200)
    start_date: date
    source_type: Literal["manual", "medical_order", "outpatient_record", "imported"]
    source_document_id: str | None = None
    event_date: date
    note: str | None = Field(default=None, max_length=500)


class MedicationUpdate(MedicationInstruction):
    event_type: Literal["started", "adjusted", "continued", "stopped"]
    event_date: date
    end_date: date | None = None
    current_status: Literal["active", "stopped", "unknown"] | None = None
    stop_source: Literal["written_order", "verbal_doctor", "patient_self", "other"] | None = None
    change_reason: str | None = Field(default=None, max_length=500)
    note: str | None = Field(default=None, max_length=500)
    updated_at: datetime

    @model_validator(mode="after")
    def require_stop_metadata(self) -> MedicationUpdate:
        if self.event_type == "stopped" and self.stop_source is None:
            raise ValueError("stop_source is required when stopping a medication")
        return self


class MedicationDailyUpsert(StrictRequest):
    record_date: date
    intake_status: Literal["taken", "missed", "unrecorded"]
    actual_dosage: float | None = Field(default=None, ge=0)
    actual_dosage_unit: str | None = Field(default=None, max_length=50)
    note: str | None = Field(default=None, max_length=500)


class CycleInput(StrictRequest):
    start_date: date
    end_date: date | None = None
    flow_level: Literal["light", "medium", "heavy", "unknown"] | None = None
    note: str | None = Field(default=None, max_length=500)
    source_type: Literal["manual", "imported"] = "manual"
    updated_at: datetime | None = None

    @model_validator(mode="after")
    def validate_dates(self) -> CycleInput:
        if self.end_date is not None and self.end_date < self.start_date:
            raise ValueError("end_date cannot be earlier than start_date")
        return self


class WeightInput(StrictRequest):
    measured_at: datetime
    weight_kg: float = Field(ge=20, le=350)
    source_type: Literal["manual", "imported"] = "manual"
    note: str | None = Field(default=None, max_length=500)
