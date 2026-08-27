from __future__ import annotations

from datetime import UTC, date, datetime
from decimal import Decimal

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.admin.health_seed import seed_health_data
from pomi_backend.db.models import (
    Medication,
    MedicationDaily,
    MenstrualCycle,
    UserAccount,
    WeightRecord,
)
from pomi_backend.repositories import (
    MedicationDailyRepository,
    MedicationRepository,
    MenstrualCycleRepository,
    PatientRepository,
    WeightRepository,
)


def account(session: Session, name: str) -> UserAccount:
    value = UserAccount(account_name=name, password_hash="synthetic-test-hash")
    session.add(value)
    session.flush()
    return value


def test_repositories_enforce_patient_scope_and_soft_delete(db_session: Session) -> None:
    first = account(db_session, "health-first")
    second = account(db_session, "health-second")
    patients = PatientRepository(db_session)
    first_patient = patients.get_or_create(first.uid)
    second_patient = patients.get_or_create(second.uid)

    medication = MedicationRepository(db_session, first_patient.patient_id).add(
        Medication(
            patient_id=first_patient.patient_id,
            drug_name="Metformin",
            source_category="prescribed",
        )
    )
    assert MedicationRepository(db_session, second_patient.patient_id).get(medication.id) is None
    with pytest.raises(ValueError):
        MedicationRepository(db_session, second_patient.patient_id).add(medication)

    cycle_repository = MenstrualCycleRepository(db_session, first_patient.patient_id)
    cycle = cycle_repository.add(
        MenstrualCycle(patient_id=first_patient.patient_id, start_date=date(2026, 8, 1))
    )
    assert cycle_repository.soft_delete(cycle.id, datetime.now(UTC)) is True
    assert cycle_repository.list() == []


def test_daily_and_weight_uniqueness_and_unrecorded_constraint(db_session: Session) -> None:
    owner = account(db_session, "health-unique")
    patient = PatientRepository(db_session).get_or_create(owner.uid)
    medication = MedicationRepository(db_session, patient.patient_id).add(
        Medication(
            patient_id=patient.patient_id,
            drug_name="Vitamin D",
            source_category="supplement",
        )
    )
    daily_repository = MedicationDailyRepository(db_session, patient.patient_id)
    daily_repository.add(
        MedicationDaily(
            patient_id=patient.patient_id,
            medication_id=medication.id,
            record_date=date(2026, 8, 27),
            intake_status="taken",
            recorded_by_uid=owner.uid,
        )
    )
    assert daily_repository.clear(medication.id, date(2026, 8, 27)) is True
    assert daily_repository.find(medication.id, date(2026, 8, 27)) is None
    db_session.commit()

    db_session.add(
        MedicationDaily(
            patient_id=patient.patient_id,
            medication_id=medication.id,
            record_date=date(2026, 8, 27),
            intake_status="unrecorded",
            recorded_by_uid=owner.uid,
        )
    )
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()

    weights = WeightRepository(db_session, patient.patient_id)
    weights.add(
        WeightRecord(
            patient_id=patient.patient_id,
            record_date=date(2026, 8, 27),
            weight_kg=Decimal("63.5"),
        )
    )
    db_session.commit()
    with pytest.raises(IntegrityError):
        weights.add(
            WeightRecord(
                patient_id=patient.patient_id,
                record_date=date(2026, 8, 27),
                weight_kg=Decimal("63.4"),
            )
        )


def test_synthetic_health_seed_is_idempotent_and_keeps_new_user_empty(
    db_session: Session,
) -> None:
    new_account = account(db_session, "health-new")
    returning_account = account(db_session, "health-returning")
    db_session.commit()

    first = seed_health_data(
        db_session,
        new_account_uid=new_account.uid,
        returning_account_uid=returning_account.uid,
        business_date=date(2026, 8, 27),
    )
    second = seed_health_data(
        db_session,
        new_account_uid=new_account.uid,
        returning_account_uid=returning_account.uid,
        business_date=date(2026, 8, 27),
    )
    assert first.created_rows == 9
    assert second.created_rows == 0
    assert (
        db_session.scalar(
            select(func.count())
            .select_from(Medication)
            .where(Medication.patient_id == first.new_patient_id)
        )
        == 0
    )
    assert len(MedicationRepository(db_session, first.returning_patient_id).list()) == 1
    assert len(WeightRepository(db_session, first.returning_patient_id).list()) == 3
