"""Asynchronous OCR task, draft, confirmation, and retry API."""

from typing import Annotated

from fastapi import APIRouter, Body, Header, Request, status

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import OcrServiceDependency
from pomi_backend.schemas.ocr import OcrConfirmRequest, OcrRetryRequest, OcrTaskCreate
from pomi_backend.services.ocr import draft_result_data, task_data

router = APIRouter(prefix="/api/ocr/tasks", tags=["ocr"])
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)]


@router.post("", status_code=status.HTTP_202_ACCEPTED)
def create_task(
    payload: OcrTaskCreate,
    request: Request,
    service: OcrServiceDependency,
    idempotency_key: IdempotencyKey,
) -> dict:
    return success(request, task_data(service.create(payload, idempotency_key)))


@router.get("/{task_id}")
def get_task(
    task_id: str,
    request: Request,
    service: OcrServiceDependency,
) -> dict:
    return success(request, task_data(service.owned_task(task_id)))


@router.get("/{task_id}/result")
def get_result(
    task_id: str,
    request: Request,
    service: OcrServiceDependency,
) -> dict:
    task, result, fields = service.result(task_id)
    return success(request, draft_result_data(task, result, fields))


@router.post("/{task_id}/confirm")
def confirm_result(
    task_id: str,
    payload: OcrConfirmRequest,
    request: Request,
    service: OcrServiceDependency,
    idempotency_key: IdempotencyKey,
) -> dict:
    del idempotency_key
    return success(request, service.confirm(task_id, payload))


@router.post("/{task_id}/retry", status_code=status.HTTP_202_ACCEPTED)
def retry_task(
    task_id: str,
    request: Request,
    service: OcrServiceDependency,
    idempotency_key: IdempotencyKey,
    payload: Annotated[OcrRetryRequest | None, Body()] = None,
) -> dict:
    del payload
    previous = service.owned_task(task_id)
    task = service.create(
        OcrTaskCreate(
            document_id=previous.document_id,
            document_revision_id=previous.document_revision_id,
            force_new_attempt=True,
        ),
        idempotency_key,
    )
    return success(request, task_data(task))
