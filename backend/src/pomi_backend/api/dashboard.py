"""Dashboard aggregate API."""

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Request

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import HealthRecordServiceDependency

router = APIRouter(prefix="/api", tags=["dashboard"])


@router.get("/dashboard")
def get_dashboard(
    request: Request,
    service: HealthRecordServiceDependency,
    target_date: Annotated[date | None, Query(alias="date")] = None,
) -> dict:
    return success(request, service.dashboard(target_date or date.today()))
