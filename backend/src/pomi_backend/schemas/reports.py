"""Medication reconciliation, patient-note, report, and rule request schemas."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Literal

from pydantic import Field, model_validator

from pomi_backend.schemas.health import StrictRequest


class ReconciliationCreate(StrictRequest):
    source_document_id: str
    medical_order_ids: list[str] = Field(default_factory=list)


class ReconciliationItemDecision(StrictRequest):
    item_id: str
    user_decision: Literal["accept", "keep_existing", "confirm_stopped", "needs_review"]
    decision_note: str | None = Field(default=None, max_length=500)
    stop_date: date | None = None
    stop_source: Literal["written_order", "verbal_doctor", "patient_self", "other"] | None = None

    @model_validator(mode="after")
    def stopped_fields(self) -> ReconciliationItemDecision:
        if self.user_decision == "confirm_stopped" and (
            self.stop_date is None or self.stop_source is None
        ):
            raise ValueError("stop_date and stop_source are required")
        return self


class ReconciliationUpdate(StrictRequest):
    status: Literal["confirmed", "cancelled"]
    items: list[ReconciliationItemDecision] = Field(min_length=1)


class PatientNoteInput(StrictRequest):
    original_text: str = Field(min_length=1, max_length=5000)
    confirmed_text: str | None = Field(default=None, max_length=5000)
    confirmation_status: Literal["draft", "confirmed", "cancelled"]

    @model_validator(mode="after")
    def confirmed_requires_text(self) -> PatientNoteInput:
        if self.confirmation_status == "confirmed" and not self.confirmed_text:
            raise ValueError("confirmed_text is required")
        return self


class ReportCreate(StrictRequest):
    patient_note_id: str | None = None
    include_sections: (
        list[
            Literal[
                "profile",
                "patient_note",
                "medications",
                "labs",
                "imaging",
                "outpatient",
                "cycles",
                "weights",
            ]
        ]
        | None
    ) = None


class DeterministicRuleUpdate(StrictRequest):
    parameters: dict[str, Any]
    priority: int
    enabled: bool
    updated_at: datetime
