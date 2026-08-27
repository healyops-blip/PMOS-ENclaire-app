"""Medication versioning, event history, and dynamic daily-state rules."""

from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    Medication,
    MedicationDaily,
    MedicationEvent,
    PatientProfile,
    UserAccount,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.schemas.medications import (
    MedicationCreate,
    MedicationDailyUpsert,
    MedicationUpdate,
)


def _iso(value: date | datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


def _number(value: Decimal | None) -> float | None:
    return float(value) if value is not None else None


def instruction_data(medication: Medication) -> dict[str, Any]:
    return {
        "drug_name": medication.drug_name,
        "specification": medication.specification,
        "dosage_value": _number(medication.dosage_value),
        "dosage_unit": medication.dosage_unit,
        "frequency": medication.frequency,
        "route": medication.route,
        "status": medication.status,
        "start_date": _iso(medication.start_date),
        "end_date": _iso(medication.end_date),
    }


def medication_data(medication: Medication) -> dict[str, Any]:
    return {
        "id": medication.id,
        "patient_id": medication.patient_id,
        **instruction_data(medication),
        "source_category": medication.source_category,
        "replaces_medication_id": medication.replaces_medication_id,
        "created_at": _iso(medication.created_at),
        "updated_at": _iso(medication.updated_at),
    }


def event_data(event: MedicationEvent) -> dict[str, Any]:
    return {
        "id": event.id,
        "medication_id": event.medication_id,
        "event_type": event.event_type,
        "event_date": _iso(event.event_date),
        "old_instruction": event.old_instruction,
        "new_instruction": event.new_instruction,
        "source_type": event.source_type,
        "source_document_id": event.source_document_id,
        "stop_source": event.stop_source,
        "note": event.note,
        "acted_by_uid": event.acted_by_uid,
        "created_at": _iso(event.created_at),
    }


def daily_data(
    medication: Medication,
    record_date: date,
    record: MedicationDaily | None,
) -> dict[str, Any]:
    return {
        "id": record.id if record is not None else None,
        "medication_id": medication.id,
        "record_date": record_date.isoformat(),
        "intake_status": record.intake_status if record is not None else "unrecorded",
        "recorded_at": _iso(record.recorded_at) if record is not None else None,
    }


class MedicationService:
    def __init__(
        self,
        session: Session,
        account: UserAccount,
        business_date: date,
    ) -> None:
        self.session = session
        self.account = account
        self.business_date = business_date

    def profile(self) -> PatientProfile:
        profile = self.session.scalar(
            select(PatientProfile).where(PatientProfile.account_uid == self.account.uid)
        )
        if profile is None:
            profile = PatientProfile(account_uid=self.account.uid)
            self.session.add(profile)
            self.session.flush()
        return profile

    def owned(self, medication_id: str) -> Medication:
        medication = self.session.scalar(
            select(Medication).where(
                Medication.id == medication_id,
                Medication.patient_id == self.profile().patient_id,
            )
        )
        if medication is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Medication was not found.", 404)
        return medication

    def list(self, status: str | None = None) -> list[Medication]:
        records = self._all_medications()
        superseded_ids = {
            item.replaces_medication_id
            for item in records
            if item.replaces_medication_id is not None
        }
        records = [item for item in records if item.id not in superseded_ids]
        if status is not None:
            records = [item for item in records if item.status == status]
        return records

    def _all_medications(self) -> list[Medication]:
        return list(
            self.session.scalars(
                select(Medication)
                .where(Medication.patient_id == self.profile().patient_id)
                .order_by(Medication.created_at.desc())
            )
        )

    def create(
        self, payload: MedicationCreate, idempotency_key: str
    ) -> tuple[Medication, MedicationEvent]:
        profile = self.profile()
        existing = self.session.scalar(
            select(Medication).where(
                Medication.patient_id == profile.patient_id,
                Medication.idempotency_key == idempotency_key,
            )
        )
        if existing is not None:
            event = self.session.scalar(
                select(MedicationEvent)
                .where(MedicationEvent.medication_id == existing.id)
                .order_by(MedicationEvent.created_at)
                .limit(1)
            )
            if event is None:
                raise BusinessError("RESOURCE_NOT_FOUND", "Medication event was not found.", 404)
            return existing, event

        medication = Medication(
            patient_id=profile.patient_id,
            drug_name=payload.drug_name.strip(),
            source_category=payload.source_category,
            specification=payload.specification,
            dosage_value=payload.dosage_value,
            dosage_unit=payload.dosage_unit,
            frequency=payload.frequency,
            route=payload.route,
            status="active",
            start_date=payload.start_date,
            idempotency_key=idempotency_key,
        )
        self.session.add(medication)
        self.session.flush()
        event = MedicationEvent(
            patient_id=profile.patient_id,
            medication_id=medication.id,
            event_type="created",
            event_date=payload.event_date,
            new_instruction=instruction_data(medication),
            source_type=payload.source_type,
            source_document_id=payload.source_document_id,
            acted_by_uid=self.account.uid,
            note=payload.note,
        )
        self.session.add(event)
        self.session.commit()
        self.session.refresh(medication)
        self.session.refresh(event)
        return medication, event

    def update(
        self, medication_id: str, payload: MedicationUpdate
    ) -> tuple[Medication, MedicationEvent]:
        medication = self.owned(medication_id)
        if medication.updated_at != payload.updated_at:
            raise BusinessError("RESOURCE_VERSION_CONFLICT", "The medication has changed.", 409)
        if medication.start_date is not None and payload.event_date < medication.start_date:
            raise BusinessError(
                "INVALID_EVENT_DATE", "The event cannot precede the medication version.", 422
            )
        latest_event_date = self.session.scalar(
            select(func.max(MedicationEvent.event_date)).where(
                MedicationEvent.patient_id == medication.patient_id,
                MedicationEvent.medication_id == medication.id,
            )
        )
        if latest_event_date is not None and payload.event_date < latest_event_date:
            raise BusinessError(
                "INVALID_EVENT_DATE", "The event cannot precede the latest event.", 422
            )

        if payload.event_type == "adjusted":
            return self._adjust(medication, payload)
        expected_status = {
            "paused": "active",
            "resumed": "paused",
            "stopped": medication.status,
        }[payload.event_type]
        if payload.event_type == "stopped":
            if medication.status not in {"active", "paused"}:
                self._invalid_transition(medication, payload.event_type)
        elif medication.status != expected_status:
            self._invalid_transition(medication, payload.event_type)

        old = instruction_data(medication)
        medication.status = {
            "paused": "paused",
            "resumed": "active",
            "stopped": "stopped",
        }[payload.event_type]
        if payload.event_type == "stopped":
            medication.end_date = payload.event_date
        medication.updated_at = utc_now()
        event = self._new_event(medication, payload, old)
        self.session.add(event)
        self.session.commit()
        self.session.refresh(medication)
        self.session.refresh(event)
        return medication, event

    def _adjust(
        self, medication: Medication, payload: MedicationUpdate
    ) -> tuple[Medication, MedicationEvent]:
        if medication.status == "stopped":
            self._invalid_transition(medication, payload.event_type)
        old = instruction_data(medication)
        values = {
            "drug_name": medication.drug_name,
            "specification": medication.specification,
            "dosage_value": medication.dosage_value,
            "dosage_unit": medication.dosage_unit,
            "frequency": medication.frequency,
            "route": medication.route,
        }
        for field in values:
            if field in payload.model_fields_set:
                values[field] = getattr(payload, field)
        if values == {
            "drug_name": medication.drug_name,
            "specification": medication.specification,
            "dosage_value": medication.dosage_value,
            "dosage_unit": medication.dosage_unit,
            "frequency": medication.frequency,
            "route": medication.route,
        }:
            raise BusinessError("NO_INSTRUCTION_CHANGE", "The instruction is unchanged.", 422)

        previous_status = medication.status
        medication.status = "stopped"
        medication.end_date = max(
            medication.start_date or payload.event_date,
            payload.event_date - timedelta(days=1),
        )
        medication.updated_at = utc_now()
        replacement = Medication(
            patient_id=medication.patient_id,
            source_category=medication.source_category,
            status=previous_status,
            start_date=payload.event_date,
            replaces_medication_id=medication.id,
            **values,
        )
        self.session.add(replacement)
        self.session.flush()
        event = MedicationEvent(
            patient_id=replacement.patient_id,
            medication_id=replacement.id,
            event_type="adjusted",
            event_date=payload.event_date,
            old_instruction=old,
            new_instruction=instruction_data(replacement),
            source_type="manual",
            acted_by_uid=self.account.uid,
            note=payload.note or payload.change_reason,
        )
        self.session.add(event)
        self.session.commit()
        self.session.refresh(replacement)
        self.session.refresh(event)
        return replacement, event

    def _new_event(
        self,
        medication: Medication,
        payload: MedicationUpdate,
        old: dict[str, Any],
    ) -> MedicationEvent:
        return MedicationEvent(
            patient_id=medication.patient_id,
            medication_id=medication.id,
            event_type=payload.event_type,
            event_date=payload.event_date,
            old_instruction=old,
            new_instruction=instruction_data(medication),
            source_type="manual",
            acted_by_uid=self.account.uid,
            note=payload.note or payload.change_reason,
            stop_source=payload.stop_source,
        )

    @staticmethod
    def _invalid_transition(medication: Medication, event_type: str) -> None:
        raise BusinessError(
            "INVALID_MEDICATION_TRANSITION",
            f"Cannot apply {event_type} while medication is {medication.status}.",
            409,
        )

    def events(self, medication_id: str) -> list[MedicationEvent]:
        medication = self.owned(medication_id)
        medications = self._all_medications()
        by_id = {item.id: item for item in medications}
        root_id = medication.id
        while by_id[root_id].replaces_medication_id in by_id:
            root_id = by_id[root_id].replaces_medication_id  # type: ignore[assignment]
        chain_ids = {root_id}
        changed = True
        while changed:
            changed = False
            for item in medications:
                if item.replaces_medication_id in chain_ids and item.id not in chain_ids:
                    chain_ids.add(item.id)
                    changed = True
        return list(
            self.session.scalars(
                select(MedicationEvent)
                .where(
                    MedicationEvent.patient_id == medication.patient_id,
                    MedicationEvent.medication_id.in_(chain_ids),
                )
                .order_by(MedicationEvent.event_date, MedicationEvent.created_at)
            )
        )

    def set_daily_status(
        self, medication_id: str, payload: MedicationDailyUpsert
    ) -> dict[str, Any]:
        medication = self.owned(medication_id)
        if payload.record_date != self.business_date:
            raise BusinessError(
                "HISTORICAL_DAILY_STATUS_READ_ONLY",
                "Only today's medication status can be changed.",
                409,
                details={"business_date": self.business_date.isoformat()},
            )
        if not self._is_expected(medication, payload.record_date):
            raise BusinessError(
                "MEDICATION_NOT_DUE", "The medication is not active on this date.", 409
            )
        record = self.session.scalar(
            select(MedicationDaily).where(
                MedicationDaily.medication_id == medication.id,
                MedicationDaily.record_date == payload.record_date,
            )
        )
        if payload.intake_status == "unrecorded":
            if record is not None:
                self.session.delete(record)
                self.session.commit()
            return daily_data(medication, payload.record_date, None)
        if record is None:
            record = MedicationDaily(
                patient_id=medication.patient_id,
                medication_id=medication.id,
                record_date=payload.record_date,
                intake_status=payload.intake_status,
                recorded_by_uid=self.account.uid,
            )
            self.session.add(record)
        else:
            if record.intake_status == payload.intake_status:
                return daily_data(medication, payload.record_date, record)
            record.intake_status = payload.intake_status
            record.recorded_at = utc_now()
        try:
            self.session.commit()
        except IntegrityError:
            self.session.rollback()
            record = self.session.scalar(
                select(MedicationDaily).where(
                    MedicationDaily.patient_id == medication.patient_id,
                    MedicationDaily.medication_id == medication.id,
                    MedicationDaily.record_date == payload.record_date,
                )
            )
            if record is None:
                raise
            if record.intake_status != payload.intake_status:
                record.intake_status = payload.intake_status
                record.recorded_at = utc_now()
                self.session.commit()
        self.session.refresh(record)
        return daily_data(medication, payload.record_date, record)

    def daily_range(
        self,
        from_date: date,
        to_date: date,
        medication_id: str | None = None,
    ) -> dict[str, Any]:
        if to_date < from_date or (to_date - from_date).days > 366:
            raise BusinessError("VALIDATION_ERROR", "Invalid date range.", 422)
        effective_to = min(to_date, self.business_date)
        if medication_id is not None:
            medications = [self.owned(medication_id)]
        else:
            medications = self._all_medications()
        explicit = {
            (record.medication_id, record.record_date): record
            for record in self.session.scalars(
                select(MedicationDaily).where(
                    MedicationDaily.patient_id == self.profile().patient_id,
                    MedicationDaily.record_date >= from_date,
                    MedicationDaily.record_date <= effective_to,
                )
            )
        }
        items: list[dict[str, Any]] = []
        counts = {"taken": 0, "missed": 0, "unrecorded": 0}
        if from_date <= effective_to:
            current = from_date
            while current <= effective_to:
                for medication in medications:
                    if not self._is_expected(medication, current):
                        continue
                    record = explicit.get((medication.id, current))
                    item = daily_data(medication, current, record)
                    items.append(item)
                    counts[item["intake_status"]] += 1
                current += timedelta(days=1)
        return {
            "from": from_date.isoformat(),
            "to": effective_to.isoformat(),
            "items": items,
            "taken_count": counts["taken"],
            "missed_count": counts["missed"],
            "unrecorded_count": counts["unrecorded"],
        }

    def _is_expected(self, medication: Medication, target: date) -> bool:
        if medication.start_date is not None and target < medication.start_date:
            return False
        child_start = self.session.scalar(
            select(Medication.start_date)
            .where(Medication.replaces_medication_id == medication.id)
            .order_by(Medication.start_date)
            .limit(1)
        )
        if child_start is not None and target >= child_start:
            return False
        events = list(
            self.session.scalars(
                select(MedicationEvent)
                .where(
                    MedicationEvent.medication_id == medication.id,
                    MedicationEvent.event_date <= target,
                )
                .order_by(MedicationEvent.event_date, MedicationEvent.created_at)
            )
        )
        active = False
        for event in events:
            if event.event_type in {"created", "resumed"}:
                active = True
            elif event.event_type in {"paused", "stopped"}:
                active = False
            elif event.event_type == "adjusted":
                active = (event.new_instruction or {}).get("status") == "active"
        return active


def grouped_medications(records: list[Medication]) -> dict[str, list[dict[str, Any]]]:
    groups: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        groups[record.source_category].append(medication_data(record))
    return {
        category: groups[category] for category in ("prescribed", "supplement", "other_long_term")
    }
