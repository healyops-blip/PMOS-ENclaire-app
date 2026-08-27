"""Strict user-confirmation and reconciliation request contracts."""

from datetime import date
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class MedicalOrderConfirmationItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    index: int = Field(ge=0)
    confirmed: Literal[True]
    drug_name: str = Field(min_length=1, max_length=200)
    specification: str | None = Field(default=None, max_length=200)
    dosage_value: Decimal = Field(gt=0, le=100000)
    dosage_unit: str = Field(min_length=1, max_length=32)
    frequency: str = Field(min_length=1, max_length=200)
    course: str | None = Field(default=None, max_length=200)
    route: str | None = Field(default=None, max_length=80)
    instructions: str | None = Field(default=None, max_length=2000)
    order_date: date
    raw_order_text: str = Field(min_length=1, max_length=10000)
    explicitly_stopped: bool = False


class MedicalOrderConfirmation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[MedicalOrderConfirmationItem] = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def unique_indexes(self) -> "MedicalOrderConfirmation":
        indexes = [item.index for item in self.items]
        if len(indexes) != len(set(indexes)):
            raise ValueError("each medication index must be confirmed once")
        return self


class ReconciliationCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    ocr_task_id: str = Field(min_length=1, max_length=36)


class ReconciliationDecision(BaseModel):
    model_config = ConfigDict(extra="forbid")

    item_id: str = Field(min_length=1, max_length=36)
    decision: Literal["accept", "keep_current", "reject"]
    note: str | None = Field(default=None, max_length=500)
    stop_date: date | None = None
    stop_source: str | None = Field(default=None, max_length=80)


class ReconciliationExecute(BaseModel):
    model_config = ConfigDict(extra="forbid")

    decisions: list[ReconciliationDecision] = Field(min_length=1, max_length=200)

    @model_validator(mode="after")
    def unique_items(self) -> "ReconciliationExecute":
        ids = [item.item_id for item in self.decisions]
        if len(ids) != len(set(ids)):
            raise ValueError("each reconciliation item needs one decision")
        return self
