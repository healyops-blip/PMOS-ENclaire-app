"""Current-patient profile API."""

from fastapi import APIRouter, Request

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import HealthRecordServiceDependency
from pomi_backend.schemas.health import PatientProfileUpdate
from pomi_backend.services.health_records import profile_data

router = APIRouter(prefix="/api/patient", tags=["patient"])


@router.get("/profile")
def get_profile(request: Request, service: HealthRecordServiceDependency) -> dict:
    profile = service.profile()
    return success(request, profile_data(profile, service.latest_cycle_start(profile.patient_id)))


@router.put("/profile")
def update_profile(
    payload: PatientProfileUpdate,
    request: Request,
    service: HealthRecordServiceDependency,
) -> dict:
    profile = service.update_profile(payload)
    return success(request, profile_data(profile, service.latest_cycle_start(profile.patient_id)))
