"""Validated request bodies for medication history and daily tracking."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")


class MedicationInstruction(StrictRequest):
    drug_name: str | None = Field(default=None, min_length=1, max_length=200)
    standard_drug_id: str | None = Field(default=None, min_length=1, max_length=80)
    specification: str | None = Field(default=None, max_length=200)
    dosage_value: Decimal | None = Field(default=None, ge=0)
    dosage_unit: str | None = Field(default=None, max_length=32)
    frequency: str | None = Field(default=None, max_length=200)
    route: str | None = Field(default=None, max_length=80)


class MedicationCreate(MedicationInstruction):
    drug_name: str = Field(min_length=1, max_length=200)
    source_category: Literal["prescribed", "supplement", "other_long_term"]
    start_date: date | None = None
    event_date: date | None = None
    source_type: Literal["manual", "medical_order", "outpatient_record", "imported"] = "manual"
    source_document_id: str | None = None
    note: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def event_cannot_precede_start(self) -> MedicationCreate:
        if (
            self.start_date is not None
            and self.event_date is not None
            and self.event_date < self.start_date
        ):
            raise ValueError("event_date cannot precede start_date")
        return self


class MedicationUpdate(MedicationInstruction):
    event_type: Literal["adjusted", "paused", "resumed", "stopped"]
    event_date: date
    stop_source: Literal["written_order", "verbal_doctor", "patient_self", "other"] | None = None
    change_reason: str | None = Field(default=None, max_length=500)
    note: str | None = Field(default=None, max_length=500)
    updated_at: datetime

    @model_validator(mode="after")
    def validate_action_fields(self) -> MedicationUpdate:
        instruction_fields = {
            "drug_name",
            "specification",
            "dosage_value",
            "dosage_unit",
            "frequency",
            "route",
        }
        supplied_instruction = bool(self.model_fields_set & instruction_fields)
        if self.event_type == "adjusted" and not supplied_instruction:
            raise ValueError("an adjusted event must change an instruction field")
        if self.event_type != "adjusted" and supplied_instruction:
            raise ValueError("instruction fields can only be changed by an adjusted event")
        if self.event_type == "stopped" and self.stop_source is None:
            raise ValueError("stop_source is required when stopping a medication")
        return self


class MedicationDailyUpsert(StrictRequest):
    record_date: date
    intake_status: Literal["taken", "missed", "unrecorded"]
