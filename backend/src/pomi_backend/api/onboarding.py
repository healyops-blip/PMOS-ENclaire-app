"""Authenticated resumable onboarding endpoints."""

from fastapi import APIRouter, Request

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import OnboardingServiceDependency
from pomi_backend.schemas.onboarding import (
    OnboardingBasicInput,
    OnboardingCycleInput,
    OnboardingMedicationsInput,
)
from pomi_backend.services.onboarding import draft_data
from pomi_backend.services.patient import profile_data

router = APIRouter(prefix="/api/onboarding", tags=["onboarding"])


@router.get("")
def get_draft(request: Request, service: OnboardingServiceDependency) -> dict:
    return success(request, draft_data(service.draft()))


@router.put("/steps/basic")
def save_basic(
    payload: OnboardingBasicInput, request: Request, service: OnboardingServiceDependency
) -> dict:
    return success(request, draft_data(service.save_basic(payload)))


@router.put("/steps/cycle")
def save_cycle(
    payload: OnboardingCycleInput, request: Request, service: OnboardingServiceDependency
) -> dict:
    return success(request, draft_data(service.save_cycle(payload)))


@router.put("/steps/medications")
def save_medications(
    payload: OnboardingMedicationsInput, request: Request, service: OnboardingServiceDependency
) -> dict:
    return success(request, draft_data(service.save_medications(payload)))


@router.post("/complete")
def complete(request: Request, service: OnboardingServiceDependency) -> dict:
    account, profile = service.complete()
    return success(
        request,
        {
            "account": {
                "uid": account.uid,
                "account_name": account.account_name,
                "phone_number": account.phone_number,
                "onboarding_completed": account.onboarding_completed,
            },
            "profile": profile_data(profile),
        },
    )
