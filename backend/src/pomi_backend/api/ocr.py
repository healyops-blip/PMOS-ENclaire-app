"""Authenticated OCR task API; processing is delegated to a separate worker."""

from __future__ import annotations

from fastapi import APIRouter, Request, status
from pydantic import BaseModel, ConfigDict, Field

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import OCRTaskServiceDependency
from pomi_backend.services.ocr import task_data

router = APIRouter(prefix="/api/ocr/tasks", tags=["ocr"])


class CreateOCRTaskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    document_id: str
    document_revision_id: str


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
    return success(request, {**task_data(task), "reused": not created})


@router.get("/{task_id}")
def get_ocr_task(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    return success(request, task_data(service.owned(task_id)))


@router.get("/{task_id}/result")
def get_ocr_result(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    return success(request, service.result(service.owned(task_id)))


@router.post("/{task_id}/confirm")
def confirm_ocr_lab(
    task_id: str,
    payload: ConfirmLabRequest,
    request: Request,
    service: OCRTaskServiceDependency,
) -> dict:
    return success(
        request,
        service.confirm_lab(task_id, payload.model_dump(mode="json")),
    )


@router.post("/{task_id}/retry", status_code=status.HTTP_201_CREATED)
def retry_ocr_task(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    task, created = service.retry(task_id)
    return success(request, {**task_data(task), "reused": not created})
