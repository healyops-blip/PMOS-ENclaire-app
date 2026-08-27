"""Authenticated OCR task API; processing is delegated to a separate worker."""

from __future__ import annotations

from fastapi import APIRouter, Request, status
from pydantic import BaseModel, ConfigDict

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import MedicalOrderServiceDependency, OCRTaskServiceDependency
from pomi_backend.schemas.orders import MedicalOrderConfirmation
from pomi_backend.services.ocr import task_data
from pomi_backend.services.orders import medical_order_data

router = APIRouter(prefix="/api/ocr/tasks", tags=["ocr"])


class CreateOCRTaskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    document_id: str
    document_revision_id: str


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


@router.post("/{task_id}/retry", status_code=status.HTTP_201_CREATED)
def retry_ocr_task(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    task, created = service.retry(task_id)
    return success(request, {**task_data(task), "reused": not created})


@router.post("/{task_id}/confirm", status_code=status.HTTP_201_CREATED)
def confirm_medical_order(
    task_id: str,
    payload: MedicalOrderConfirmation,
    request: Request,
    service: MedicalOrderServiceDependency,
) -> dict:
    orders, created = service.confirm(task_id, payload)
    return success(
        request,
        {"items": [medical_order_data(order) for order in orders], "reused": not created},
    )
