"""Authenticated OCR task API; processing is delegated to a separate worker."""

from __future__ import annotations

from fastapi import APIRouter, Request, status
from pydantic import BaseModel, ConfigDict, Field

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import (
    ClinicalTextConfirmationServiceDependency,
    MedicalOrderServiceDependency,
    OCRTaskServiceDependency,
)
from pomi_backend.schemas.clinical_text import ClinicalTextConfirmRequest
from pomi_backend.schemas.orders import MedicalOrderConfirmation
from pomi_backend.services.orders import medical_order_data, medical_order_p0

router = APIRouter(prefix="/api/ocr/tasks", tags=["ocr"])


class CreateOCRTaskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    document_id: str
    document_revision_id: str


class UseFallbackRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    accept: bool
    data_version: str = Field(min_length=1, max_length=40)


class LabConfirmationItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_index: int | None = Field(default=None, ge=0)
    name: str | None = None
    value: str | int | float | None = None
    unit: str | None = None
    reference_range: str | None = None
    sample_date: str | None = None
    exam_date: str | None = None
    report_date: str | None = None
    visit_date: str | None = None
    note: str | None = Field(default=None, max_length=1000)


class ConfirmLabRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    result_id: str
    expected_revision_id: str
    visit_id: str | None = Field(default=None, max_length=100)
    sample_date: str | None = None
    exam_date: str | None = None
    report_date: str | None = None
    visit_date: str | None = None
    items: list[LabConfirmationItem] = Field(max_length=200)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_ocr_task(
    payload: CreateOCRTaskRequest,
    request: Request,
    service: OCRTaskServiceDependency,
) -> dict:
    task, created = service.create(payload.document_id, payload.document_revision_id)
    return success(request, {**service.data(task), "reused": not created})


@router.get("/{task_id}")
def get_ocr_task(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    return success(request, service.data(service.owned(task_id)))


@router.get("/{task_id}/result")
def get_ocr_result(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    return success(request, service.result(service.owned(task_id)))


@router.get("/{task_id}/fallback")
def get_fallback_eligibility(
    task_id: str, request: Request, service: OCRTaskServiceDependency
) -> dict:
    return success(request, service.fallback_eligibility(task_id))


@router.post("/{task_id}/fallback")
def use_ocr_fallback(
    task_id: str,
    payload: UseFallbackRequest,
    request: Request,
    service: OCRTaskServiceDependency,
) -> dict:
    return success(
        request,
        service.use_fallback(task_id, accept=payload.accept, data_version=payload.data_version),
    )


@router.post("/{task_id}/confirm")
def confirm_ocr_lab(
    task_id: str,
    payload: ConfirmLabRequest | ClinicalTextConfirmRequest | MedicalOrderConfirmation,
    request: Request,
    lab_service: OCRTaskServiceDependency,
    clinical_service: ClinicalTextConfirmationServiceDependency,
    order_service: MedicalOrderServiceDependency,
) -> dict:
    if isinstance(payload, ClinicalTextConfirmRequest):
        return success(request, clinical_service.confirm(task_id, payload))
    if isinstance(payload, MedicalOrderConfirmation):
        orders, created = order_service.confirm(task_id, payload)
        return success(
            request,
            {
                "items": [medical_order_data(order) for order in orders],
                "reused": not created,
                "p0_evaluation": medical_order_p0(orders),
            },
        )
    return success(
        request,
        lab_service.confirm_lab(task_id, payload.model_dump(mode="json")),
    )


@router.post("/{task_id}/retry", status_code=status.HTTP_201_CREATED)
def retry_ocr_task(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    task, created = service.retry(task_id)
    return success(request, {**service.data(task), "reused": not created})
