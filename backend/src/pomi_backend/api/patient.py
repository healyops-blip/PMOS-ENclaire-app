"""Authenticated patient profile API."""

from fastapi import APIRouter, Request

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import PatientProfileServiceDependency
from pomi_backend.schemas.patient import PatientProfileUpdate
from pomi_backend.services.patient import profile_data

router = APIRouter(prefix="/api/patient", tags=["patient"])


@router.get("/profile")
def get_profile(request: Request, service: PatientProfileServiceDependency) -> dict:
    return success(request, profile_data(service.profile()))


@router.put("/profile")
def update_profile(
    payload: PatientProfileUpdate,
    request: Request,
    service: PatientProfileServiceDependency,
) -> dict:
    return success(request, profile_data(service.update(payload)))
