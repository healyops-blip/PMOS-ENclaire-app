"""Patient statement request schemas."""

from pydantic import BaseModel, ConfigDict, Field


class PatientNoteCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    original_text: str = Field(max_length=5000)
    visit_context: str | None = Field(default=None, max_length=200)


class PatientNoteUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    original_text: str = Field(max_length=5000)
    visit_context: str | None = Field(default=None, max_length=200)


class PatientNoteCopy(BaseModel):
    model_config = ConfigDict(extra="forbid")

    visit_context: str | None = Field(default=None, max_length=200)
