"""Patient profile request contracts."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class PatientProfileUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    nickname: str | None = Field(default=None, min_length=1, max_length=80)
    birth_date: date | None = None
    gender: Literal["female", "male", "other", "prefer_not_to_say"] | None = None
    height_cm: Decimal | None = Field(default=None, ge=100, le=230, decimal_places=1)
    diagnosis_year: int | None = Field(default=None, ge=1900, le=2100)
    primary_condition: str | None = Field(default=None, min_length=1, max_length=80)
    next_visit_date: date | None = None
    health_goal: str | None = Field(default=None, max_length=500)
    complete_onboarding: bool = False
    updated_at: datetime | None = None

    @model_validator(mode="after")
    def dates_are_plausible(self) -> PatientProfileUpdate:
        if self.birth_date is not None and self.birth_date > date.today():
            raise ValueError("birth_date cannot be in the future")
        return self
