"""OCR task creation, confirmation, and retry request schemas."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import Field, model_validator

from pomi_backend.schemas.health import StrictRequest

DocumentType = Literal["lab_report", "medical_order", "imaging_text_report", "outpatient_record"]


class OcrTaskCreate(StrictRequest):
    document_id: str
    document_revision_id: str
    force_new_attempt: bool = False


class FieldConfirmation(StrictRequest):
    field_path: str = Field(min_length=1, max_length=500)
    user_value: Any = None
    confirmation_status: Literal["confirmed", "edited", "rejected"]


class OcrConfirmRequest(StrictRequest):
    result_id: str
    expected_revision_id: str
    document_type: DocumentType
    confirmed_data: dict[str, Any]
    field_confirmations: list[FieldConfirmation]
    confirm_all: bool = False

    @model_validator(mode="after")
    def confirmation_scope(self) -> OcrConfirmRequest:
        if self.confirm_all and self.document_type != "lab_report":
            raise ValueError("confirm_all is allowed only for lab reports")
        if not self.confirm_all and not self.field_confirmations:
            raise ValueError("field_confirmations are required")
        return self


class OcrRetryRequest(StrictRequest):
    reason: str | None = Field(default=None, max_length=500)
    allow_registered_fallback: bool = True
