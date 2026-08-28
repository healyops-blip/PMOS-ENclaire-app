"""Patient-owned weight record use cases."""

from __future__ import annotations

from datetime import date
from datetime import UTC

from sqlalchemy.orm import Session

from pomi_backend.db.models import UserAccount, WeightRecord
from pomi_backend.repositories import PatientRepository, WeightRepository
from pomi_backend.schemas.weights import WeightInput


class WeightRecordNotFound(Exception):
    """Raised when a record is absent from the authenticated patient scope."""


class WeightDateConflict(Exception):
    """Raised when moving a record onto a date that already has a record."""


class WeightService:
    def __init__(self, session: Session, account: UserAccount) -> None:
        self._session = session
        patient = PatientRepository(session).get_or_create(account.uid)
        self._repository = WeightRepository(session, patient.patient_id)

    def list(
        self,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> list[WeightRecord]:
        return self._repository.list(from_date=from_date, to_date=to_date)

    def upsert(self, payload: WeightInput) -> tuple[WeightRecord, bool]:
        record = self._repository.find_by_date(payload.record_date)
        created = record is None
        if record is None:
            record = self._repository.add(
                WeightRecord(
                    patient_id=self._repository.patient_id,
                    record_date=payload.record_date,
                    weight_kg=payload.weight_kg,
                )
            )
        else:
            self._repository.update(record, weight_kg=payload.weight_kg)
        self._session.commit()
        self._session.refresh(record)
        return record, created

    def update(self, record_id: str, payload: WeightInput) -> WeightRecord:
        record = self._repository.get(record_id)
        if record is None:
            raise WeightRecordNotFound
        if payload.updated_at is None or _as_utc(payload.updated_at) != _as_utc(record.updated_at):
            raise WeightVersionConflict

        same_day = self._repository.find_by_date(payload.record_date)
        if same_day is not None and same_day.id != record.id:
            raise WeightDateConflict

        self._repository.update(
            record,
            record_date=payload.record_date,
            weight_kg=payload.weight_kg,
        )
        self._session.commit()
        self._session.refresh(record)
        return record


class WeightVersionConflict(Exception):
    """Raised when an update uses a stale or missing record version."""


def _as_utc(value):
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)
