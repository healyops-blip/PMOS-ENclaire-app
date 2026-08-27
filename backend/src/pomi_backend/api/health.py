"""Process and database health checks."""

from fastapi import APIRouter
from sqlalchemy import text

from pomi_backend.api.dependencies import DatabaseSession
from pomi_backend.schemas.health import HealthResponse

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live", response_model=HealthResponse, include_in_schema=False)
def liveness() -> HealthResponse:
    return HealthResponse()


@router.get("/ready", response_model=HealthResponse, include_in_schema=False)
def readiness(session: DatabaseSession) -> HealthResponse:
    session.execute(text("SELECT 1"))
    return HealthResponse()
