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
    update_fields = frozenset(
        {
            "nickname",
            "birth_date",
            "gender",
            "height_cm",
            "diagnosis_year",
            "primary_condition",
            "next_visit_date",
            "health_goal",
            "onboarding_completed",
            "onboarding_completed_at",
            "updated_at",
        }
    )

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

    def update(self, profile: PatientProfile, **changes: Any) -> PatientProfile:
        owned = self.get_by_account_uid(profile.account_uid)
        if owned is None or owned.patient_id != profile.patient_id:
            raise ValueError("patient profile is outside repository scope")
        unsupported = changes.keys() - self.update_fields
        if unsupported:
            fields = ", ".join(sorted(unsupported))
            raise ValueError(f"fields are not updateable: {fields}")
        for field, value in changes.items():
            setattr(owned, field, value)
        self.session.flush()
        return owned


class PatientScopedRepository:
    model: type[Any]
    update_fields: frozenset[str] = frozenset()

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
        self._validate_associations(record)
        self.session.add(record)
        self.session.flush()
        return record

    def _validate_associations(self, record: Record) -> None:
        """Validate patient-owned references before relying on database constraints."""

    def _apply_changes(self, record: Record, changes: dict[str, Any]) -> Record:
        unsupported = changes.keys() - self.update_fields
        if unsupported:
            fields = ", ".join(sorted(unsupported))
            raise ValueError(f"fields are not updateable: {fields}")
        for field, value in changes.items():
            setattr(record, field, value)
        self.session.flush()
        return record


class MedicationRepository(PatientScopedRepository):
    model = Medication
    update_fields = frozenset(
        {
            "drug_name",
            "source_category",
            "specification",
            "dosage_value",
            "dosage_unit",
            "frequency",
            "route",
            "status",
            "start_date",
            "end_date",
        }
    )

    def list(self, *, status: str | None = None) -> list[Medication]:
        statement = select(Medication).where(Medication.patient_id == self.patient_id)
        if status is not None:
            statement = statement.where(Medication.status == status)
        return list(self.session.scalars(statement.order_by(Medication.created_at.desc())))

    def update(self, medication: Medication, **changes: Any) -> Medication:
        owned_medication = self.get(medication.id)
        if owned_medication is None:
            raise ValueError("medication is outside repository scope")
        return self._apply_changes(owned_medication, changes)

    def _validate_associations(self, record: Record) -> None:
        if isinstance(record, Medication) and record.replaces_medication_id is not None:
            if self.get(record.replaces_medication_id) is None:
                raise ValueError("replacement medication is outside repository scope")


class MedicationEventRepository(PatientScopedRepository):
    model = MedicationEvent

    def _validate_associations(self, record: Record) -> None:
        if isinstance(record, MedicationEvent):
            medication = MedicationRepository(self.session, self.patient_id).get(
                record.medication_id
            )
            if medication is None:
                raise ValueError("event medication is outside repository scope")

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

    def _validate_associations(self, record: Record) -> None:
        if isinstance(record, MedicationDaily):
            medication = MedicationRepository(self.session, self.patient_id).get(
                record.medication_id
            )
            if medication is None:
                raise ValueError("daily medication is outside repository scope")

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
    update_fields = frozenset({"start_date", "end_date", "flow_level", "note", "source_type"})

    def get(self, record_id: str) -> MenstrualCycle | None:
        return self.session.scalar(
            select(MenstrualCycle).where(
                MenstrualCycle.id == record_id,
                MenstrualCycle.patient_id == self.patient_id,
                MenstrualCycle.deleted_at.is_(None),
            )
        )

    def list(
        self,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> list[MenstrualCycle]:
        statement = select(MenstrualCycle).where(
            MenstrualCycle.patient_id == self.patient_id,
            MenstrualCycle.deleted_at.is_(None),
        )
        if from_date is not None:
            statement = statement.where(MenstrualCycle.start_date >= from_date)
        if to_date is not None:
            statement = statement.where(MenstrualCycle.start_date <= to_date)
        return list(
            self.session.scalars(
                statement.order_by(
                    MenstrualCycle.start_date.desc(),
                    MenstrualCycle.created_at.desc(),
                )
            )
        )

    def active(self, cycle_id: str) -> MenstrualCycle | None:
        cycle = self.get(cycle_id)
        if cycle is None or cycle.deleted_at is not None:
            return None
        return cycle

    def update(self, cycle: MenstrualCycle, **changes: Any) -> MenstrualCycle:
        active_cycle = self.get(cycle.id)
        if active_cycle is None:
            raise ValueError("cycle is outside repository scope")
        return self._apply_changes(active_cycle, changes)

    def soft_delete(self, cycle_id: str, deleted_at: Any) -> bool:
        cycle = self.get(cycle_id)
        if cycle is None or cycle.deleted_at is not None:
            return False
        cycle.deleted_at = deleted_at
        self.session.flush()
        return True


class WeightRepository(PatientScopedRepository):
    model = WeightRecord
    update_fields = frozenset({"record_date", "weight_kg"})

    def list(
        self,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> list[WeightRecord]:
        statement = select(WeightRecord).where(WeightRecord.patient_id == self.patient_id)
        if from_date is not None:
            statement = statement.where(WeightRecord.record_date >= from_date)
        if to_date is not None:
            statement = statement.where(WeightRecord.record_date <= to_date)
        return list(
            self.session.scalars(
                statement.order_by(WeightRecord.record_date, WeightRecord.created_at)
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
        owned_record = self.get(record.id)
        if owned_record is None:
            raise ValueError("weight record is outside repository scope")
        return self._apply_changes(owned_record, changes)
