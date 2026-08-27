"""Strict user-confirmed clinical text payloads."""

from __future__ import annotations

from datetime import date
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class FieldConfirmation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    field_path: str = Field(min_length=1, max_length=300)
    user_value: Any = None
    confirmation_status: Literal["confirmed", "edited", "rejected"]


class ClinicalTextConfirmRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    result_id: str
    expected_revision_id: str
    document_type: Literal["imaging_text_report", "outpatient_record"]
    confirmed_data: dict[str, Any]
    field_confirmations: list[FieldConfirmation] = Field(default_factory=list)
    confirm_all: bool = False


class ImagingTextConfirmation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    facility: str | None = Field(default=None, max_length=200)
    examination_name: str | None = Field(default=None, max_length=200)
    body_part: str | None = Field(default=None, max_length=200)
    modality: str | None = Field(default=None, max_length=100)
    examination_date: date | None = None
    report_date: date | None = None
    findings: str = Field(min_length=1, max_length=20000)
    impression: str = Field(min_length=1, max_length=20000)

    @field_validator("findings", "impression")
    @classmethod
    def non_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("critical original text cannot be blank")
        return value


class OutpatientConfirmation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    facility: str | None = Field(default=None, max_length=200)
    department: str | None = Field(default=None, max_length=200)
    doctor_name: str | None = Field(default=None, max_length=100)
    visit_date: date
    chief_complaint: str | None = Field(default=None, max_length=20000)
    diagnosis_summary: str = Field(min_length=1, max_length=20000)
    treatment_plan: str | None = Field(default=None, max_length=20000)
    medical_advice: str = Field(min_length=1, max_length=20000)

    @field_validator("diagnosis_summary", "medical_advice")
    @classmethod
    def non_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("critical original text cannot be blank")
        return value
