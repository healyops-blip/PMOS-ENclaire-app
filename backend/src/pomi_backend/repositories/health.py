"""Patient-scoped repositories for foundational health records."""

from __future__ import annotations

from datetime import date
from typing import Any, TypeVar

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.db.models.health import (
    Medication,
    MedicationDaily,
    MedicationEvent,
    MenstrualCycle,
    PatientProfile,
    WeightRecord,
)

Record = TypeVar(
    "Record", Medication, MedicationEvent, MedicationDaily, MenstrualCycle, WeightRecord
)


class PatientRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get_by_account_uid(self, account_uid: str) -> PatientProfile | None:
        return self.session.scalar(
            select(PatientProfile).where(PatientProfile.account_uid == account_uid)
        )

    def get_or_create(self, account_uid: str) -> PatientProfile:
        profile = self.get_by_account_uid(account_uid)
        if profile is None:
            profile = PatientProfile(account_uid=account_uid)
            self.session.add(profile)
            self.session.flush()
        return profile


class PatientScopedRepository:
    model: type[Any]

    def __init__(self, session: Session, patient_id: str) -> None:
        self.session = session
        self.patient_id = patient_id

    def get(self, record_id: str) -> Any | None:
        return self.session.scalar(
            select(self.model).where(
                self.model.id == record_id,
                self.model.patient_id == self.patient_id,
            )
        )

    def add(self, record: Record) -> Record:
        if record.patient_id != self.patient_id:
            raise ValueError("record patient does not match repository scope")
        self.session.add(record)
        self.session.flush()
        return record


class MedicationRepository(PatientScopedRepository):
    model = Medication

    def list(self, *, status: str | None = None) -> list[Medication]:
        statement = select(Medication).where(Medication.patient_id == self.patient_id)
        if status is not None:
            statement = statement.where(Medication.status == status)
        return list(self.session.scalars(statement.order_by(Medication.created_at.desc())))

    def update(self, medication: Medication, **changes: Any) -> Medication:
        if self.get(medication.id) is None:
            raise ValueError("medication is outside repository scope")
        for field, value in changes.items():
            setattr(medication, field, value)
        self.session.flush()
        return medication


class MedicationEventRepository(PatientScopedRepository):
    model = MedicationEvent

    def list_for_medication(self, medication_id: str) -> list[MedicationEvent]:
        return list(
            self.session.scalars(
                select(MedicationEvent)
                .where(
                    MedicationEvent.patient_id == self.patient_id,
                    MedicationEvent.medication_id == medication_id,
                )
                .order_by(MedicationEvent.event_date, MedicationEvent.created_at)
            )
        )


class MedicationDailyRepository(PatientScopedRepository):
    model = MedicationDaily

    def find(self, medication_id: str, record_date: date) -> MedicationDaily | None:
        return self.session.scalar(
            select(MedicationDaily).where(
                MedicationDaily.patient_id == self.patient_id,
                MedicationDaily.medication_id == medication_id,
                MedicationDaily.record_date == record_date,
            )
        )

    def list_range(self, from_date: date, to_date: date) -> list[MedicationDaily]:
        return list(
            self.session.scalars(
                select(MedicationDaily)
                .where(
                    MedicationDaily.patient_id == self.patient_id,
                    MedicationDaily.record_date >= from_date,
                    MedicationDaily.record_date <= to_date,
                )
                .order_by(MedicationDaily.record_date, MedicationDaily.medication_id)
            )
        )

    def clear(self, medication_id: str, record_date: date) -> bool:
        record = self.find(medication_id, record_date)
        if record is None:
            return False
        self.session.delete(record)
        self.session.flush()
        return True


class MenstrualCycleRepository(PatientScopedRepository):
    model = MenstrualCycle

    def list(self) -> list[MenstrualCycle]:
        return list(
            self.session.scalars(
                select(MenstrualCycle)
                .where(
                    MenstrualCycle.patient_id == self.patient_id,
                    MenstrualCycle.deleted_at.is_(None),
                )
                .order_by(MenstrualCycle.start_date.desc())
            )
        )

    def update(self, cycle: MenstrualCycle, **changes: Any) -> MenstrualCycle:
        if self.get(cycle.id) is None:
            raise ValueError("cycle is outside repository scope")
        for field, value in changes.items():
            setattr(cycle, field, value)
        self.session.flush()
        return cycle

    def soft_delete(self, cycle_id: str, deleted_at: Any) -> bool:
        cycle = self.get(cycle_id)
        if cycle is None or cycle.deleted_at is not None:
            return False
        cycle.deleted_at = deleted_at
        self.session.flush()
        return True


class WeightRepository(PatientScopedRepository):
    model = WeightRecord

    def list(self) -> list[WeightRecord]:
        return list(
            self.session.scalars(
                select(WeightRecord)
                .where(WeightRecord.patient_id == self.patient_id)
                .order_by(WeightRecord.record_date)
            )
        )

    def find_by_date(self, record_date: date) -> WeightRecord | None:
        return self.session.scalar(
            select(WeightRecord).where(
                WeightRecord.patient_id == self.patient_id,
                WeightRecord.record_date == record_date,
            )
        )

    def update(self, record: WeightRecord, **changes: Any) -> WeightRecord:
        if self.get(record.id) is None:
            raise ValueError("weight record is outside repository scope")
        for field, value in changes.items():
            setattr(record, field, value)
        self.session.flush()
        return record
