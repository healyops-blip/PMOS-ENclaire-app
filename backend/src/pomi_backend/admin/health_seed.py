"""Idempotent synthetic health-record fixtures for local development."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy.orm import Session

from pomi_backend.db.models import (
    Medication,
    MedicationDaily,
    MedicationEvent,
    MenstrualCycle,
    WeightRecord,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.repositories import PatientRepository

SEED_NAMESPACE = uuid.UUID("7880114f-6cf2-429a-8acb-29af45220f15")


def _id(account_uid: str, label: str) -> str:
    return str(uuid.uuid5(SEED_NAMESPACE, f"{account_uid}:{label}"))


@dataclass(frozen=True, slots=True)
class HealthSeedResult:
    new_patient_id: str
    returning_patient_id: str
    created_rows: int


def seed_health_data(
    session: Session,
    *,
    new_account_uid: str,
    returning_account_uid: str,
    business_date: date | None = None,
) -> HealthSeedResult:
    """Create no health records for the new user and deterministic demo rows for the old user."""

    today = business_date or date.today()
    patient_repository = PatientRepository(session)
    new_patient = patient_repository.get_or_create(new_account_uid)
    returning_patient = patient_repository.get_or_create(returning_account_uid)
    if not returning_patient.onboarding_completed:
        returning_patient.onboarding_completed = True
        returning_patient.onboarding_completed_at = utc_now()
    created_rows = 0

    medication_id = _id(returning_account_uid, "medication-metformin")
    medication = session.get(Medication, medication_id)
    if medication is None:
        medication = Medication(
            id=medication_id,
            patient_id=returning_patient.patient_id,
            drug_name="Metformin",
            source_category="prescribed",
            specification="500 mg",
            dosage_value=Decimal("500"),
            dosage_unit="mg",
            frequency="once daily",
            route="oral",
            start_date=today.replace(day=1),
        )
        session.add(medication)
        session.add(
            MedicationEvent(
                id=_id(returning_account_uid, "event-metformin-created"),
                patient_id=returning_patient.patient_id,
                medication_id=medication.id,
                event_type="created",
                event_date=medication.start_date,
                new_instruction={
                    "drug_name": medication.drug_name,
                    "dosage_value": "500",
                    "dosage_unit": "mg",
                    "frequency": medication.frequency,
                },
                source_type="synthetic_seed",
                acted_by_uid=returning_account_uid,
            )
        )
        created_rows += 2

    for offset, status in ((0, "taken"), (1, "missed"), (2, "taken")):
        record_date = today - timedelta(days=offset)
        record_id = _id(returning_account_uid, f"daily-{record_date.isoformat()}")
        if session.get(MedicationDaily, record_id) is None:
            session.add(
                MedicationDaily(
                    id=record_id,
                    patient_id=returning_patient.patient_id,
                    medication_id=medication.id,
                    record_date=record_date,
                    intake_status=status,
                    recorded_by_uid=returning_account_uid,
                )
            )
            created_rows += 1

    cycle_start = today - timedelta(days=20)
    cycle_id = _id(returning_account_uid, "cycle-current")
    if session.get(MenstrualCycle, cycle_id) is None:
        session.add(
            MenstrualCycle(
                id=cycle_id,
                patient_id=returning_patient.patient_id,
                start_date=cycle_start,
                end_date=cycle_start + timedelta(days=4),
                note="Synthetic demonstration record",
            )
        )
        created_rows += 1

    for offset, value in ((14, "64.1"), (7, "63.8"), (0, "63.5")):
        record_date = today - timedelta(days=offset)
        record_id = _id(returning_account_uid, f"weight-{record_date.isoformat()}")
        if session.get(WeightRecord, record_id) is None:
            session.add(
                WeightRecord(
                    id=record_id,
                    patient_id=returning_patient.patient_id,
                    record_date=record_date,
                    weight_kg=Decimal(value),
                )
            )
            created_rows += 1

    session.commit()
    return HealthSeedResult(
        new_patient_id=new_patient.patient_id,
        returning_patient_id=returning_patient.patient_id,
        created_rows=created_rows,
    )
