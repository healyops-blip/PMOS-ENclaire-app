"""Read-only API for user-confirmed laboratory observations."""

from fastapi import APIRouter, Request

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import OCRTaskServiceDependency

router = APIRouter(prefix="/api/lab-observations", tags=["laboratory"])


@router.get("")
def list_lab_observations(request: Request, service: OCRTaskServiceDependency) -> dict:
    return success(request, {"items": service.list_lab_observations()})


@router.get("/{observation_id}")
def get_lab_observation(
    observation_id: str,
    request: Request,
    service: OCRTaskServiceDependency,
) -> dict:
    return success(request, service.lab_observation(observation_id))
