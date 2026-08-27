from __future__ import annotations

from datetime import UTC, date, datetime
from decimal import Decimal

import pytest
from sqlalchemy import func, inspect, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.admin.health_seed import seed_health_data
from pomi_backend.db.models import (
    Medication,
    MedicationDaily,
    MedicationEvent,
    MenstrualCycle,
    UserAccount,
    WeightRecord,
)
from pomi_backend.repositories import (
    MedicationDailyRepository,
    MedicationEventRepository,
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
    assert cycle_repository.get(cycle.id) is None
    with pytest.raises(ValueError, match="outside repository scope"):
        cycle_repository.update(cycle, note="must remain deleted")


def test_repository_updates_reject_identity_and_ownership_fields(db_session: Session) -> None:
    first = account(db_session, "health-update-first")
    second = account(db_session, "health-update-second")
    patients = PatientRepository(db_session)
    first_patient = patients.get_or_create(first.uid)
    second_patient = patients.get_or_create(second.uid)
    medications = MedicationRepository(db_session, first_patient.patient_id)
    medication = medications.add(
        Medication(
            patient_id=first_patient.patient_id,
            drug_name="Metformin",
            source_category="prescribed",
        )
    )

    with pytest.raises(ValueError, match="patient_id"):
        medications.update(medication, patient_id=second_patient.patient_id)
    with pytest.raises(ValueError, match="id"):
        medications.update(medication, id="replacement-id")
    with pytest.raises(ValueError, match="created_at"):
        medications.update(medication, created_at=datetime.now(UTC))

    assert medication.patient_id == first_patient.patient_id
    assert medication.id != "replacement-id"


def test_medication_associations_must_remain_in_patient_scope(db_session: Session) -> None:
    first = account(db_session, "health-association-first")
    second = account(db_session, "health-association-second")
    patients = PatientRepository(db_session)
    first_patient = patients.get_or_create(first.uid)
    second_patient = patients.get_or_create(second.uid)
    first_medication = MedicationRepository(db_session, first_patient.patient_id).add(
        Medication(
            patient_id=first_patient.patient_id,
            drug_name="Metformin",
            source_category="prescribed",
        )
    )

    with pytest.raises(ValueError, match="replacement medication"):
        MedicationRepository(db_session, second_patient.patient_id).add(
            Medication(
                patient_id=second_patient.patient_id,
                drug_name="Metformin XR",
                source_category="prescribed",
                replaces_medication_id=first_medication.id,
            )
        )
    with pytest.raises(ValueError, match="daily medication"):
        MedicationDailyRepository(db_session, second_patient.patient_id).add(
            MedicationDaily(
                patient_id=second_patient.patient_id,
                medication_id=first_medication.id,
                record_date=date(2026, 8, 27),
                intake_status="taken",
                recorded_by_uid=second.uid,
            )
        )
    with pytest.raises(ValueError, match="event medication"):
        MedicationEventRepository(db_session, second_patient.patient_id).add(
            MedicationEvent(
                patient_id=second_patient.patient_id,
                medication_id=first_medication.id,
                event_type="created",
                event_date=date(2026, 8, 27),
                acted_by_uid=second.uid,
            )
        )

    inspector = inspect(db_session.get_bind())
    daily_foreign_keys = inspector.get_foreign_keys("medication_daily")
    event_foreign_keys = inspector.get_foreign_keys("medication_event")
    medication_foreign_keys = inspector.get_foreign_keys("medication")
    assert ["patient_id", "medication_id"] in [
        key["constrained_columns"] for key in daily_foreign_keys
    ]
    assert ["patient_id", "medication_id"] in [
        key["constrained_columns"] for key in event_foreign_keys
    ]
    assert ["patient_id", "replaces_medication_id"] in [
        key["constrained_columns"] for key in medication_foreign_keys
    ]

    db_session.commit()
    db_session.add(
        MedicationDaily(
            patient_id=second_patient.patient_id,
            medication_id=first_medication.id,
            record_date=date(2026, 8, 28),
            intake_status="taken",
            recorded_by_uid=second.uid,
        )
    )
    with pytest.raises(IntegrityError):
        db_session.flush()


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
