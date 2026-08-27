"""Medication maintenance, version history, and daily three-state API."""

from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Header, Query, Request, status

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import MedicationServiceDependency
from pomi_backend.schemas.medications import (
    MedicationCreate,
    MedicationDailyUpsert,
    MedicationUpdate,
)
from pomi_backend.services.medications import (
    event_data,
    grouped_medications,
    medication_data,
)

router = APIRouter(prefix="/api", tags=["medications"])
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)]


@router.get("/medications")
def list_medications(
    request: Request,
    service: MedicationServiceDependency,
    medication_status: Annotated[
        Literal["active", "paused", "stopped"] | None, Query(alias="status")
    ] = None,
) -> dict:
    records = service.list(medication_status)
    return success(
        request,
        {
            "server_date": service.business_date.isoformat(),
            "items": [medication_data(record) for record in records],
            "groups": grouped_medications(records),
            "next_cursor": None,
            "has_more": False,
        },
    )


@router.post("/medications", status_code=status.HTTP_201_CREATED)
def create_medication(
    payload: MedicationCreate,
    request: Request,
    service: MedicationServiceDependency,
    idempotency_key: IdempotencyKey,
) -> dict:
    medication, event = service.create(payload, idempotency_key)
    return success(
        request,
        {"medication": medication_data(medication), "event": event_data(event)},
    )


@router.put("/medications/{medication_id}")
def update_medication(
    medication_id: str,
    payload: MedicationUpdate,
    request: Request,
    service: MedicationServiceDependency,
) -> dict:
    medication, event = service.update(medication_id, payload)
    return success(
        request,
        {"medication": medication_data(medication), "event": event_data(event)},
    )


@router.get("/medications/{medication_id}/events")
def list_medication_events(
    medication_id: str,
    request: Request,
    service: MedicationServiceDependency,
) -> dict:
    return success(
        request,
        [event_data(event) for event in service.events(medication_id)],
    )


@router.put("/medications/{medication_id}/daily-status")
def set_daily_status(
    medication_id: str,
    payload: MedicationDailyUpsert,
    request: Request,
    service: MedicationServiceDependency,
) -> dict:
    return success(request, service.set_daily_status(medication_id, payload))


@router.get("/medication-daily")
def list_daily_records(
    request: Request,
    service: MedicationServiceDependency,
    from_date: Annotated[date, Query(alias="from")],
    to_date: Annotated[date, Query(alias="to")],
    medication_id: str | None = None,
) -> dict:
    return success(request, service.daily_range(from_date, to_date, medication_id))
