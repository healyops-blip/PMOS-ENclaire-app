"""Stable dashboard aggregation response contracts."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class DashboardSectionError(BaseModel):
    code: str
    message: str
    retryable: bool = True


class DashboardSection(BaseModel):
    status: Literal["ok", "empty", "error"]
    data: Any = None
    error_code: str | None = None
    error: DashboardSectionError | None = None


class DashboardData(BaseModel):
    server_date: str
    data_as_of: str
    follow_up: DashboardSection
    today_medications: DashboardSection
    monthly_medication_summary: DashboardSection
    tracking_summary: DashboardSection
    document_summary: DashboardSection
    latest_report: DashboardSection


class DashboardEnvelope(BaseModel):
    success: bool = True
    data: DashboardData
    request_id: str
    error: None = Field(default=None)
