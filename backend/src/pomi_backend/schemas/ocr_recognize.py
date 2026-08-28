"""Synchronous algorithm OCR response contract."""

from __future__ import annotations

from datetime import date
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class OCRExamination(BaseModel):
    model_config = ConfigDict(extra="allow")
    item_name: str
    value: str | int | float | None = None
    unit: str | None = None
    reference_range: str | None = None
    abnormal: bool | None = None


class OCRMedicationSuggestion(BaseModel):
    model_config = ConfigDict(extra="allow")
    drug_name: str
    dosage: str | None = None
    frequency: str | None = None
    duration: str | None = None
    instruction: str | None = None
    source_text: str | None = None


class OCRRecognizeData(BaseModel):
    model_config = ConfigDict(extra="allow")
    hospital: str | None = None
    department: str | None = None
    visit_date: date | None = None
    diagnosis_summary: str | None = None
    medical_advice: str | None = None
    examinations: list[OCRExamination] = Field(default_factory=list)
    medication_suggestions: list[OCRMedicationSuggestion] = Field(default_factory=list)
    original_file_name: str
    evidence: list[dict[str, Any]] | None = None
