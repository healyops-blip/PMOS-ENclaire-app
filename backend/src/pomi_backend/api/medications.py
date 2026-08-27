"""Medication history and three-state daily tracking API."""

from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Header, Query, Request, status

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import HealthRecordServiceDependency
from pomi_backend.schemas.health import (
    MedicationCreate,
    MedicationDailyUpsert,
    MedicationUpdate,
)
from pomi_backend.services.health_records import daily_data, event_data, medication_data

router = APIRouter(prefix="/api", tags=["medications"])
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)]


@router.get("/medications")
def list_medications(
    request: Request,
    service: HealthRecordServiceDependency,
    medication_status: Annotated[
        Literal["active", "stopped", "unknown"] | None, Query(alias="status")
    ] = None,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> dict:
    records = service.medications(medication_status, limit, cursor)
    page = records[:limit]
    return success(
        request,
        {
            "items": [medication_data(record) for record in page],
            "next_cursor": page[-1].created_at.isoformat() if len(records) > limit else None,
            "has_more": len(records) > limit,
        },
    )


@router.post("/medications", status_code=status.HTTP_201_CREATED)
def create_medication(
    payload: MedicationCreate,
    request: Request,
    service: HealthRecordServiceDependency,
    idempotency_key: IdempotencyKey,
) -> dict:
    medication, event = service.create_medication(payload, idempotency_key)
    return success(
        request,
        {"medication": medication_data(medication), "event": event_data(event)},
    )


@router.put("/medications/{medication_id}")
def update_medication(
    medication_id: str,
    payload: MedicationUpdate,
    request: Request,
    service: HealthRecordServiceDependency,
) -> dict:
    medication, event = service.update_medication(medication_id, payload)
    return success(
        request,
        {"medication": medication_data(medication), "event": event_data(event)},
    )


@router.get("/medications/{medication_id}/events")
def list_medication_events(
    medication_id: str,
    request: Request,
    service: HealthRecordServiceDependency,
) -> dict:
    return success(
        request,
        [event_data(event) for event in service.medication_events(medication_id)],
    )


@router.put("/medications/{medication_id}/daily-status")
def set_daily_status(
    medication_id: str,
    payload: MedicationDailyUpsert,
    request: Request,
    service: HealthRecordServiceDependency,
) -> dict:
    return success(request, daily_data(service.set_daily_status(medication_id, payload)))


@router.get("/medication-daily")
def list_daily_records(
    request: Request,
    service: HealthRecordServiceDependency,
    from_date: Annotated[date, Query(alias="from")],
    to_date: Annotated[date, Query(alias="to")],
    medication_id: str | None = None,
) -> dict:
    records, counts = service.daily_range(from_date, to_date, medication_id)
    return success(
        request,
        {
            "from": from_date.isoformat(),
            "to": to_date.isoformat(),
            "items": [daily_data(record) for record in records],
            "taken_count": counts["taken"],
            "missed_count": counts["missed"],
            "unrecorded_count": counts["unrecorded"],
        },
    )
