"""Menstrual-cycle and weight tracking API."""

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Request, Response, status

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import HealthRecordServiceDependency
from pomi_backend.schemas.health import CycleInput, WeightInput
from pomi_backend.services.health_records import weight_data

router = APIRouter(prefix="/api", tags=["tracking"])


@router.get("/cycles")
def list_cycles(
    request: Request,
    service: HealthRecordServiceDependency,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
) -> dict:
    return success(
        request,
        [service.cycle_data(cycle) for cycle in service.cycles(from_date, to_date)],
    )


@router.post("/cycles", status_code=status.HTTP_201_CREATED)
def create_cycle(
    payload: CycleInput,
    request: Request,
    service: HealthRecordServiceDependency,
) -> dict:
    cycle = service.save_cycle(payload)
    return success(request, service.cycle_data(cycle))


@router.put("/cycles/{cycle_id}")
def update_cycle(
    cycle_id: str,
    payload: CycleInput,
    request: Request,
    service: HealthRecordServiceDependency,
) -> dict:
    cycle = service.save_cycle(payload, cycle_id)
    return success(request, service.cycle_data(cycle))


@router.get("/weights")
def list_weights(
    request: Request,
    service: HealthRecordServiceDependency,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
) -> dict:
    return success(request, [weight_data(record) for record in service.weights(from_date, to_date)])


@router.post(
    "/weights",
    status_code=status.HTTP_201_CREATED,
    responses={status.HTTP_200_OK: {"description": "Existing same-day record updated"}},
)
def create_weight(
    payload: WeightInput,
    request: Request,
    response: Response,
    service: HealthRecordServiceDependency,
) -> dict:
    record, created = service.save_weight(payload)
    if not created:
        response.status_code = status.HTTP_200_OK
    return success(request, weight_data(record))


@router.put("/weights/{weight_id}")
def update_weight(
    weight_id: str,
    payload: WeightInput,
    request: Request,
    service: HealthRecordServiceDependency,
) -> dict:
    record, _ = service.save_weight(payload, weight_id)
    return success(request, weight_data(record))
