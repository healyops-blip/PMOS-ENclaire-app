"""Patient-scoped menstrual-cycle history use cases."""

from __future__ import annotations

from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy.orm import Session

from pomi_backend.db.models import MenstrualCycle
from pomi_backend.repositories import MenstrualCycleRepository, PatientRepository
from pomi_backend.schemas.cycles import CycleInput, MenstrualCycleResponse


class CycleError(Exception):
    code = "CYCLE_ERROR"
    message = "The cycle record could not be processed."
    status_code = 400

    def __init__(self, *, details: dict[str, Any] | None = None) -> None:
        self.details = details or {}
        super().__init__(self.message)


class CycleDateOrderError(CycleError):
    code = "CYCLE_DATE_ORDER_INVALID"
    message = "The start date must not be later than the end date."
    status_code = 422


class CycleOverlapError(CycleError):
    code = "CYCLE_DATE_OVERLAP"
    message = "This menstrual period overlaps an existing record."
    status_code = 409


class CycleNotFoundError(CycleError):
    code = "CYCLE_NOT_FOUND"
    message = "The cycle record was not found."
    status_code = 404


class CycleVersionConflictError(CycleError):
    code = "CYCLE_VERSION_CONFLICT"
    message = "The cycle record changed on another device. Refresh and try again."
    status_code = 409


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


class CycleService:
    def __init__(self, session: Session, account_uid: str) -> None:
        self._session = session
        patient = PatientRepository(session).get_or_create(account_uid)
        self._repository = MenstrualCycleRepository(session, patient.patient_id)
        self._patient_id = patient.patient_id

    def list(
        self,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> list[MenstrualCycleResponse]:
        if from_date is not None and to_date is not None and from_date > to_date:
            raise CycleDateOrderError
        all_cycles = self._repository.list()
        lengths = self._cycle_lengths(all_cycles)
        visible = [
            cycle
            for cycle in all_cycles
            if (from_date is None or cycle.start_date >= from_date)
            and (to_date is None or cycle.start_date <= to_date)
        ]
        return [self._response(cycle, lengths.get(cycle.id)) for cycle in visible]

    def create(self, payload: CycleInput) -> MenstrualCycleResponse:
        self._validate_dates(payload.start_date, payload.end_date)
        self._validate_no_overlap(payload.start_date, payload.end_date)
        cycle = self._repository.add(
            MenstrualCycle(
                patient_id=self._patient_id,
                start_date=payload.start_date,
                end_date=payload.end_date,
                flow_level=payload.flow_level,
                note=payload.note,
                source_type=payload.source_type,
            )
        )
        self._session.commit()
        self._session.refresh(cycle)
        return self._current_response(cycle.id)

    def update(self, cycle_id: str, payload: CycleInput) -> MenstrualCycleResponse:
        cycle = self._repository.active(cycle_id)
        if cycle is None:
            raise CycleNotFoundError
        if payload.updated_at is not None and _as_utc(payload.updated_at) != _as_utc(
            cycle.updated_at
        ):
            raise CycleVersionConflictError
        self._validate_dates(payload.start_date, payload.end_date)
        self._validate_no_overlap(payload.start_date, payload.end_date, excluding_id=cycle.id)
        self._repository.update(
            cycle,
            start_date=payload.start_date,
            end_date=payload.end_date,
            flow_level=payload.flow_level,
            note=payload.note,
            source_type=payload.source_type,
            updated_at=datetime.now(UTC),
        )
        self._session.commit()
        return self._current_response(cycle.id)

    def delete(self, cycle_id: str) -> None:
        cycle = self._repository.active(cycle_id)
        if cycle is None:
            raise CycleNotFoundError
        self._repository.soft_delete(cycle.id, datetime.now(UTC))
        self._session.commit()

    def _current_response(self, cycle_id: str) -> MenstrualCycleResponse:
        cycles = self._repository.list()
        lengths = self._cycle_lengths(cycles)
        cycle = next(item for item in cycles if item.id == cycle_id)
        return self._response(cycle, lengths.get(cycle.id))

    def _validate_no_overlap(
        self,
        start_date: date,
        end_date: date | None,
        *,
        excluding_id: str | None = None,
    ) -> None:
        candidate_end = end_date or date.max
        for existing in self._repository.list():
            if existing.id == excluding_id:
                continue
            existing_end = existing.end_date or date.max
            if start_date <= existing_end and existing.start_date <= candidate_end:
                raise CycleOverlapError(details={"conflicting_cycle_id": existing.id})

    @staticmethod
    def _validate_dates(start_date: date, end_date: date | None) -> None:
        if end_date is not None and start_date > end_date:
            raise CycleDateOrderError

    @staticmethod
    def _cycle_lengths(cycles: list[MenstrualCycle]) -> dict[str, int | None]:
        chronological = sorted(cycles, key=lambda cycle: (cycle.start_date, cycle.created_at))
        result: dict[str, int | None] = {}
        previous_start: date | None = None
        for cycle in chronological:
            result[cycle.id] = (
                None if previous_start is None else (cycle.start_date - previous_start).days
            )
            previous_start = cycle.start_date
        return result

    @staticmethod
    def _response(
        cycle: MenstrualCycle,
        cycle_length_days: int | None,
    ) -> MenstrualCycleResponse:
        duration_days = (
            None if cycle.end_date is None else (cycle.end_date - cycle.start_date).days + 1
        )
        return MenstrualCycleResponse(
            id=cycle.id,
            start_date=cycle.start_date,
            end_date=cycle.end_date,
            flow_level=cycle.flow_level,
            note=cycle.note,
            source_type=cycle.source_type,
            cycle_length_days=cycle_length_days,
            duration_days=duration_days,
            created_at=cycle.created_at,
            updated_at=cycle.updated_at,
        )
