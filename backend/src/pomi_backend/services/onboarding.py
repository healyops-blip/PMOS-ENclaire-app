"""Onboarding draft persistence and atomic completion."""

from __future__ import annotations

from datetime import UTC, date, datetime
from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    Medication,
    MedicationEvent,
    MenstrualCycle,
    OnboardingDraft,
    PatientProfile,
    UserAccount,
    WeightRecord,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.schemas.onboarding import (
    OnboardingBasicInput,
    OnboardingCycleInput,
    OnboardingMedicationsInput,
)


def draft_data(draft: OnboardingDraft) -> dict:
    return {
        "id": draft.id,
        "current_step": draft.current_step,
        "basic": draft.basic_data,
        "cycle": draft.cycle_data,
        "medications": draft.medications_data,
        "updated_at": draft.updated_at.isoformat(),
    }


class OnboardingService:
    def __init__(self, session: Session, account: UserAccount, business_date: date) -> None:
        self.session = session
        self.account = account
        self.business_date = business_date

    def draft(self) -> OnboardingDraft:
        draft = self.session.scalar(
            select(OnboardingDraft).where(OnboardingDraft.account_uid == self.account.uid)
        )
        if draft is None:
            draft = OnboardingDraft(account_uid=self.account.uid)
            self.session.add(draft)
            self.session.commit()
            self.session.refresh(draft)
        return draft

    def save_basic(self, payload: OnboardingBasicInput) -> OnboardingDraft:
        return self._save("basic_data", payload.model_dump(mode="json", exclude_none=False), "cycle")

    def save_cycle(self, payload: OnboardingCycleInput) -> OnboardingDraft:
        return self._save("cycle_data", payload.model_dump(mode="json", exclude_none=False), "medications")

    def save_medications(self, payload: OnboardingMedicationsInput) -> OnboardingDraft:
        return self._save(
            "medications_data",
            payload.model_dump(mode="json", exclude_none=False),
            "medications",
        )

    def _save(self, field: str, value: dict, next_step: str) -> OnboardingDraft:
        draft = self.draft()
        expected = value.pop("updated_at", None)
        if expected is not None and _as_utc(_datetime_value(expected)) != _as_utc(draft.updated_at):
            raise BusinessError("RESOURCE_VERSION_CONFLICT", "The onboarding draft has changed.", 409)
        setattr(draft, field, value)
        draft.current_step = next_step
        draft.updated_at = utc_now()
        self.session.commit()
        self.session.refresh(draft)
        return draft

    def complete(self) -> tuple[UserAccount, PatientProfile]:
        draft = self.draft()
        if draft.completed_at is not None or self.account.onboarding_completed:
            profile = self.session.scalar(
                select(PatientProfile).where(PatientProfile.account_uid == self.account.uid)
            )
            if profile is None:
                raise BusinessError("RESOURCE_NOT_FOUND", "Patient profile was not found.", 404)
            return self.account, profile
        basic = draft.basic_data or {}
        if not basic.get("nickname") or basic.get("birth_year") is None:
            raise BusinessError("ONBOARDING_BASIC_REQUIRED", "昵称和出生年份为必填项。", 422)
        profile = self.session.scalar(
            select(PatientProfile).where(PatientProfile.account_uid == self.account.uid)
        )
        if profile is None:
            profile = PatientProfile(account_uid=self.account.uid)
            self.session.add(profile)
            self.session.flush()
        profile.nickname = basic["nickname"]
        profile.birth_year = basic["birth_year"]
        profile.diagnosis_year = basic.get("diagnosis_year")
        profile.height_cm = basic.get("height_cm")
        cycle = draft.cycle_data or {}
        profile.usual_cycle_min_days = cycle.get("usual_cycle_min_days")
        profile.usual_cycle_max_days = cycle.get("usual_cycle_max_days")
        profile.next_visit_date = _date_value(cycle.get("next_visit_date"))
        profile.onboarding_completed = True
        profile.onboarding_completed_at = utc_now()
        profile.updated_at = utc_now()
        self.account.onboarding_completed = True
        if basic.get("weight_kg") is not None:
            self.session.add(
                WeightRecord(
                    patient_id=profile.patient_id,
                    record_date=self.business_date,
                    weight_kg=basic["weight_kg"],
                )
            )
        if cycle.get("last_menstrual_start_date"):
            self.session.add(
                MenstrualCycle(
                    patient_id=profile.patient_id,
                    start_date=_date_value(cycle["last_menstrual_start_date"]),
                    flow_level="unknown",
                    note="初始化记录",
                )
            )
        for item in (draft.medications_data or {}).get("items", []):
            medication = Medication(
                patient_id=profile.patient_id,
                drug_name=item["drug_name"].strip(),
                source_category=item["source_category"],
                start_date=_date_value(item.get("start_date")),
                status="active",
                idempotency_key=f"onboarding:{draft.id}:{item['drug_name']}",
            )
            self.session.add(medication)
            self.session.flush()
            self.session.add(
                MedicationEvent(
                    patient_id=profile.patient_id,
                    medication_id=medication.id,
                    event_type="created",
                    event_date=_date_value(item.get("start_date")) or self.business_date,
                    new_instruction={"drug_name": medication.drug_name},
                    source_type="manual",
                    acted_by_uid=self.account.uid,
                )
            )
        draft.current_step = "complete"
        draft.completed_at = utc_now()
        draft.updated_at = utc_now()
        self.session.commit()
        self.session.refresh(profile)
        return self.account, profile


def _date_value(value: date | str | None) -> date | None:
    if value is None or isinstance(value, date):
        return value
    return date.fromisoformat(value)


def _datetime_value(value: datetime | str) -> datetime:
    if isinstance(value, datetime):
        return value
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
