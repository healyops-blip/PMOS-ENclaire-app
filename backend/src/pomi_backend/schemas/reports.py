"""Deterministic report snapshot request schemas."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

ReportSection = Literal[
    "profile",
    "patient_note",
    "medications",
    "labs",
    "imaging",
    "outpatient",
    "cycles",
    "weights",
]


class ReportCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    patient_note_id: str | None = None
    include_sections: list[ReportSection] = Field(
        min_length=1,
        default_factory=lambda: [
            "profile",
            "patient_note",
            "medications",
            "labs",
            "imaging",
            "outpatient",
            "cycles",
            "weights",
        ],
    )
    confirm_incomplete: bool = False
