"""Authenticated weight recording and trend endpoints."""

from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status

from pomi_backend.api.dependencies import CurrentAccount, DatabaseSession
from pomi_backend.db.models import WeightRecord
from pomi_backend.schemas.weights import (
    WeightInput,
    WeightItemEnvelope,
    WeightListEnvelope,
    WeightResponse,
)
from pomi_backend.services.weights import (
    WeightDateConflict,
    WeightRecordNotFound,
    WeightService,
    WeightVersionConflict,
)

router = APIRouter(prefix="/api/weights", tags=["weights"])


def get_weight_service(session: DatabaseSession, account: CurrentAccount) -> WeightService:
    return WeightService(session, account)


WeightServiceDependency = Annotated[WeightService, Depends(get_weight_service)]


def weight_response(record: WeightRecord) -> WeightResponse:
    return WeightResponse(
        id=record.id,
        record_date=record.record_date,
        weight_kg=float(record.weight_kg),
        created_at=record.created_at,
        updated_at=record.updated_at,
    )


def request_id(request: Request, response: Response) -> str:
    value = request.state.request_id
    response.headers["X-Request-ID"] = value
    return value


@router.get("", response_model=WeightListEnvelope)
def list_weights(
    request: Request,
    response: Response,
    service: WeightServiceDependency,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
) -> WeightListEnvelope:
    if from_date is not None and to_date is not None and to_date < from_date:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="The 'to' date cannot be earlier than 'from'.",
        )
    return WeightListEnvelope(
        data=[
            weight_response(record) for record in service.list(from_date=from_date, to_date=to_date)
        ],
        request_id=request_id(request, response),
    )


@router.post(
    "",
    response_model=WeightItemEnvelope,
    status_code=status.HTTP_201_CREATED,
    responses={status.HTTP_200_OK: {"description": "Same-day record updated"}},
)
def create_weight(
    payload: WeightInput,
    request: Request,
    response: Response,
    service: WeightServiceDependency,
) -> WeightItemEnvelope:
    record, created = service.upsert(payload)
    if not created:
        response.status_code = status.HTTP_200_OK
    return WeightItemEnvelope(
        data=weight_response(record),
        request_id=request_id(request, response),
    )


@router.put(
    "/{weight_id}",
    response_model=WeightItemEnvelope,
    responses={
        status.HTTP_404_NOT_FOUND: {"description": "Record not found in patient scope"},
        status.HTTP_409_CONFLICT: {"description": "Target date already has a record"},
    },
)
def update_weight(
    weight_id: str,
    payload: WeightInput,
    request: Request,
    response: Response,
    service: WeightServiceDependency,
) -> WeightItemEnvelope:
    try:
        return WeightItemEnvelope(
            data=weight_response(service.update(weight_id, payload)),
            request_id=request_id(request, response),
        )
    except WeightRecordNotFound as error:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Weight record not found.",
        ) from error
    except WeightDateConflict as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A weight record already exists for that date.",
        ) from error
    except WeightVersionConflict as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Weight record has changed."
        ) from error
