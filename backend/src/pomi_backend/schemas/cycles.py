"""Menstrual-cycle request and response schemas."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class CycleInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    start_date: date
    end_date: date | None = None
    flow_level: Literal["light", "medium", "heavy", "unknown"] | None = None
    note: str | None = Field(default=None, max_length=500)
    source_type: Literal["manual", "imported"] = "manual"
    updated_at: datetime | None = None

    @field_validator("note")
    @classmethod
    def normalize_note(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None


class MenstrualCycleResponse(BaseModel):
    id: str
    start_date: date
    end_date: date | None
    flow_level: str | None
    note: str | None
    source_type: str
    cycle_length_days: int | None
    duration_days: int | None
    created_at: datetime
    updated_at: datetime


class ErrorDetail(BaseModel):
    code: str
    message: str
    retryable: bool = False
    details: dict[str, Any] = Field(default_factory=dict)


class CycleListEnvelope(BaseModel):
    success: Literal[True] = True
    data: list[MenstrualCycleResponse]
    request_id: str
    error: None = None


class CycleItemEnvelope(BaseModel):
    success: Literal[True] = True
    data: MenstrualCycleResponse
    request_id: str
    error: None = None


class CycleErrorEnvelope(BaseModel):
    success: Literal[False] = False
    data: None = None
    request_id: str
    error: ErrorDetail
