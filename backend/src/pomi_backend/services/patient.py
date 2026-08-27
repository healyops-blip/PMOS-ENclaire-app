"""Patient profile persistence and onboarding transaction."""

from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import PatientProfile, UserAccount
from pomi_backend.db.models.auth import utc_now
from pomi_backend.repositories import PatientRepository
from pomi_backend.schemas.patient import PatientProfileUpdate


def profile_data(profile: PatientProfile) -> dict[str, Any]:
    return {
        "patient_id": profile.patient_id,
        "nickname": profile.nickname,
        "birth_date": profile.birth_date.isoformat() if profile.birth_date else None,
        "gender": profile.gender,
        "height_cm": float(profile.height_cm) if profile.height_cm is not None else None,
        "diagnosis_year": profile.diagnosis_year,
        "primary_condition": profile.primary_condition,
        "next_visit_date": profile.next_visit_date.isoformat() if profile.next_visit_date else None,
        "health_goal": profile.health_goal,
        "onboarding_completed": profile.onboarding_completed,
        "onboarding_completed_at": profile.onboarding_completed_at.isoformat()
        if profile.onboarding_completed_at
        else None,
        "created_at": profile.created_at.isoformat(),
        "updated_at": profile.updated_at.isoformat(),
    }


class PatientProfileService:
    def __init__(self, session: Session, account: UserAccount) -> None:
        self.session = session
        self.account = account
        self.repository = PatientRepository(session)

    def profile(self) -> PatientProfile:
        profile = self.repository.get_or_create(self.account.uid)
        self.session.commit()
        self.session.refresh(profile)
        return profile

    def update(self, payload: PatientProfileUpdate) -> PatientProfile:
        profile = self.repository.get_or_create(self.account.uid)
        if payload.updated_at is not None and payload.updated_at != profile.updated_at:
            raise BusinessError(
                "RESOURCE_VERSION_CONFLICT", "The patient profile has changed.", 409
            )
        changes = {
            field: getattr(payload, field)
            for field in (
                "nickname",
                "birth_date",
                "gender",
                "height_cm",
                "diagnosis_year",
                "primary_condition",
                "next_visit_date",
                "health_goal",
            )
            if field in payload.model_fields_set
        }
        if payload.complete_onboarding and not profile.onboarding_completed:
            changes["onboarding_completed"] = True
            changes["onboarding_completed_at"] = utc_now()
            self.account.onboarding_completed = True
        changes["updated_at"] = utc_now()
        try:
            self.repository.update(profile, **changes)
            self.session.commit()
            self.session.refresh(profile)
            return profile
        except Exception:
            self.session.rollback()
            raise
