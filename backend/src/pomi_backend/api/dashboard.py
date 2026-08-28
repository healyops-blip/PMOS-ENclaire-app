"""Authenticated dashboard aggregation endpoint."""

from fastapi import APIRouter, Request

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import CurrentAccount, DatabaseSession
from pomi_backend.schemas.dashboard import DashboardEnvelope
from pomi_backend.services.dashboard import DashboardService

router = APIRouter(prefix="/api", tags=["dashboard"])


@router.get("/dashboard", response_model=DashboardEnvelope)
def get_dashboard(
    request: Request,
    session: DatabaseSession,
    account: CurrentAccount,
) -> dict:
    service = DashboardService(
        session,
        account,
        request.app.state.business_date_provider(),
    )
    return success(request, service.aggregate())
