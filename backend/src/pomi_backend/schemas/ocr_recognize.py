"""Synchronous algorithm OCR response contract."""

from __future__ import annotations

from datetime import date
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


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
    ocr_task_id: str | None = None
    ocr_result_id: str | None = None


class OCRConfirmExamination(BaseModel):
    model_config = ConfigDict(extra="forbid")
    source_index: int = Field(ge=0)
    item_name: str = Field(min_length=1, max_length=200)
    value: str | int | float
    unit: str = Field(min_length=1, max_length=40)
    reference_range: str | None = Field(default=None, max_length=120)
    note: str | None = Field(default=None, max_length=1000)


class OCRConfirmMedication(BaseModel):
    model_config = ConfigDict(extra="forbid")
    source_index: int = Field(ge=0)
    drug_name: str = Field(min_length=1, max_length=200)
    dosage: str | None = Field(default=None, max_length=100)
    frequency: str | None = Field(default=None, max_length=200)
    duration: str | None = Field(default=None, max_length=200)
    instruction: str | None = Field(default=None, max_length=2000)
    source_text: str | None = Field(default=None, max_length=10000)
    source_category: Literal["prescribed", "supplement", "other_long_term"] = "prescribed"
    start_date: date | None = None


class OCRResultConfirmRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    visit_date: date | None = None
    examinations: list[OCRConfirmExamination] = Field(default_factory=list, max_length=200)
    medication_suggestions: list[OCRConfirmMedication] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def source_indexes_are_unique(self) -> OCRResultConfirmRequest:
        for field_name in ("examinations", "medication_suggestions"):
            values = getattr(self, field_name)
            indexes = [item.source_index for item in values]
            if len(indexes) != len(set(indexes)):
                raise ValueError(f"{field_name} source_index values must be unique")
        return self
