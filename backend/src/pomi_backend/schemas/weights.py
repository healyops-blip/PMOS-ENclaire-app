"""Request and response schemas for patient weight records."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class WeightInput(BaseModel):
    """A manual weight measurement, stored in kilograms for one local date."""

    model_config = ConfigDict(extra="forbid")

    record_date: date
    weight_kg: Decimal = Field(ge=Decimal("20.0"), le=Decimal("300.0"), multiple_of=0.1)


class WeightResponse(BaseModel):
    id: str
    record_date: date
    weight_kg: float
    created_at: datetime
    updated_at: datetime


class WeightItemEnvelope(BaseModel):
    success: Literal[True] = True
    data: WeightResponse
    request_id: str
    error: None = None


class WeightListEnvelope(BaseModel):
    success: Literal[True] = True
    data: list[WeightResponse]
    request_id: str
    error: None = None
