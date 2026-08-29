"""Resumable onboarding request/response contracts."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class OnboardingBasicInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    nickname: str = Field(min_length=1, max_length=80)
    birth_year: int = Field(ge=1900, le=2100)
    diagnosis_year: int | None = Field(default=None, ge=1900, le=2100)
    height_cm: Decimal | None = Field(default=None, ge=100, le=230, decimal_places=1)
    weight_kg: Decimal | None = Field(default=None, ge=20, le=300, decimal_places=1)
    updated_at: datetime | None = None


class OnboardingCycleInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    last_menstrual_start_date: date | None = None
    usual_cycle_min_days: int | None = Field(default=None, ge=15, le=120)
    usual_cycle_max_days: int | None = Field(default=None, ge=15, le=120)
    period_duration_days: int | None = Field(default=None, ge=1, le=14)
    next_visit_date: date | None = None
    updated_at: datetime | None = None

    @model_validator(mode="after")
    def valid_range(self) -> OnboardingCycleInput:
        if (
            self.usual_cycle_min_days is not None
            and self.usual_cycle_max_days is not None
            and self.usual_cycle_min_days > self.usual_cycle_max_days
        ):
            raise ValueError("usual_cycle_min_days cannot exceed usual_cycle_max_days")
        return self


class OnboardingMedicationInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    catalog_id: str | None = None
    drug_name: str = Field(min_length=1, max_length=200)
    source_category: Literal["prescribed", "supplement", "other_long_term"]
    start_date: date | None = None


class OnboardingMedicationsInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    items: list[OnboardingMedicationInput] = Field(default_factory=list, max_length=50)
    updated_at: datetime | None = None


class OnboardingDraftResponse(BaseModel):
    id: str
    current_step: Literal["basic", "cycle", "medications", "complete"]
    basic: dict | None = None
    cycle: dict | None = None
    medications: dict | None = None
    updated_at: datetime
