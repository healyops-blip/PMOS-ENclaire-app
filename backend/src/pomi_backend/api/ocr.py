"""Authenticated OCR task API; processing is delegated to a separate worker."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Header, Request, status
from pydantic import BaseModel, ConfigDict

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import (
    ClinicalTextConfirmationServiceDependency,
    OCRTaskServiceDependency,
)
from pomi_backend.schemas.clinical_text import ClinicalTextConfirmRequest
from pomi_backend.services.ocr import task_data

router = APIRouter(prefix="/api/ocr/tasks", tags=["ocr"])
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)]


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


@router.post("/{task_id}/confirm")
def confirm_ocr_clinical_text(
    task_id: str,
    payload: ClinicalTextConfirmRequest,
    request: Request,
    service: ClinicalTextConfirmationServiceDependency,
    idempotency_key: IdempotencyKey,
) -> dict:
    del idempotency_key  # The immutable OCR result is the idempotency resource key.
    return success(request, service.confirm(task_id, payload))
