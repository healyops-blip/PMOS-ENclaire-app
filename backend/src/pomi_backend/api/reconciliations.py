"""Medication reconciliation draft, review, and atomic execution API."""

from fastapi import APIRouter, Request, status

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import ReconciliationServiceDependency
from pomi_backend.schemas.orders import ReconciliationCreate, ReconciliationExecute

router = APIRouter(prefix="/api/medication-reconciliations", tags=["medication-reconciliations"])


@router.post("", status_code=status.HTTP_201_CREATED)
def create_reconciliation(
    payload: ReconciliationCreate,
    request: Request,
    service: ReconciliationServiceDependency,
) -> dict:
    reconciliation, created = service.create(payload.ocr_task_id)
    return success(request, {**service.data(reconciliation), "reused": not created})


@router.get("/{reconciliation_id}")
def get_reconciliation(
    reconciliation_id: str,
    request: Request,
    service: ReconciliationServiceDependency,
) -> dict:
    return success(request, service.data(service.owned(reconciliation_id)))


@router.put("/{reconciliation_id}")
def execute_reconciliation(
    reconciliation_id: str,
    payload: ReconciliationExecute,
    request: Request,
    service: ReconciliationServiceDependency,
) -> dict:
    return success(request, service.data(service.execute(reconciliation_id, payload)))
