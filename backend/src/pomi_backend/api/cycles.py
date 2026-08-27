"""Authenticated menstrual-cycle history endpoints."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Request, Response, status
from fastapi.responses import JSONResponse

from pomi_backend.api.dependencies import CurrentAccount, DatabaseSession
from pomi_backend.schemas.cycles import (
    CycleErrorEnvelope,
    CycleInput,
    CycleItemEnvelope,
    CycleListEnvelope,
)
from pomi_backend.services.cycles import CycleError, CycleService

router = APIRouter(prefix="/api/cycles", tags=["cycles"])


def request_id(request: Request) -> str:
    supplied = request.headers.get("X-Request-ID", "").strip()
    return supplied[:128] if supplied else str(uuid.uuid4())


async def cycle_error_handler(request: Request, error: CycleError) -> JSONResponse:
    identifier = request_id(request)
    body = CycleErrorEnvelope(
        request_id=identifier,
        error={
            "code": error.code,
            "message": error.message,
            "retryable": False,
            "details": error.details,
        },
    )
    return JSONResponse(
        status_code=error.status_code,
        content=body.model_dump(mode="json"),
        headers={"X-Request-ID": identifier},
    )


@router.get("", response_model=CycleListEnvelope)
def list_cycles(
    request: Request,
    response: Response,
    session: DatabaseSession,
    account: CurrentAccount,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
) -> CycleListEnvelope:
    identifier = request_id(request)
    response.headers["X-Request-ID"] = identifier
    cycles = CycleService(session, account.uid).list(from_date=from_date, to_date=to_date)
    return CycleListEnvelope(data=cycles, request_id=identifier)


@router.post("", response_model=CycleItemEnvelope, status_code=status.HTTP_201_CREATED)
def create_cycle(
    payload: CycleInput,
    request: Request,
    response: Response,
    session: DatabaseSession,
    account: CurrentAccount,
) -> CycleItemEnvelope:
    identifier = request_id(request)
    response.headers["X-Request-ID"] = identifier
    cycle = CycleService(session, account.uid).create(payload)
    return CycleItemEnvelope(data=cycle, request_id=identifier)


@router.put("/{cycle_id}", response_model=CycleItemEnvelope)
def update_cycle(
    cycle_id: uuid.UUID,
    payload: CycleInput,
    request: Request,
    response: Response,
    session: DatabaseSession,
    account: CurrentAccount,
) -> CycleItemEnvelope:
    identifier = request_id(request)
    response.headers["X-Request-ID"] = identifier
    cycle = CycleService(session, account.uid).update(str(cycle_id), payload)
    return CycleItemEnvelope(data=cycle, request_id=identifier)


@router.delete("/{cycle_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_cycle(
    cycle_id: uuid.UUID,
    session: DatabaseSession,
    account: CurrentAccount,
) -> None:
    CycleService(session, account.uid).delete(str(cycle_id))
