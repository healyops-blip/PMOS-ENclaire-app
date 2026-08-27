"""Business operations for patient profiles and daily health records."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    Medication,
    MedicationDaily,
    MedicationEvent,
    MenstrualCycle,
    PatientProfile,
    ReportSnapshot,
    UserAccount,
    WeightRecord,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.schemas.health import (
    CycleInput,
    MedicationCreate,
    MedicationDailyUpsert,
    MedicationUpdate,
    PatientProfileUpdate,
    WeightInput,
)


def _iso(value: date | datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


def _instruction(medication: Medication) -> dict[str, Any]:
    return {
        "drug_name": medication.drug_name,
        "specification": medication.specification,
        "dosage_text": medication.dosage_text,
        "dosage_value": medication.dosage_value,
        "dosage_unit": medication.dosage_unit,
        "frequency": medication.frequency,
        "route": medication.route,
        "start_date": _iso(medication.start_date),
        "end_date": _iso(medication.end_date),
        "current_status": medication.current_status,
    }


def profile_data(profile: PatientProfile, last_cycle_start: date | None = None) -> dict[str, Any]:
    return {
        "patient_id": profile.patient_id,
        "account_uid": profile.account_uid,
        "nickname": profile.nickname,
        "birth_date": _iso(profile.birth_date),
        "gender": profile.gender,
        "height_cm": profile.height_cm,
        "diagnosis_year": profile.diagnosis_year,
        "primary_condition": profile.primary_condition,
        "usual_cycle_length_days": profile.usual_cycle_length_days,
        "last_menstrual_start_date": _iso(last_cycle_start),
        "next_visit_date": _iso(profile.next_visit_date),
        "health_goal": profile.health_goal,
        "onboarding_step": profile.onboarding_step,
        "onboarding_completed": profile.onboarding_completed,
        "external_ocr_notice_accepted_at": _iso(profile.external_ocr_notice_accepted_at),
        "created_at": _iso(profile.created_at),
        "updated_at": _iso(profile.updated_at),
    }


def medication_data(medication: Medication) -> dict[str, Any]:
    return {
        "id": medication.id,
        "patient_id": medication.patient_id,
        **_instruction(medication),
        "normalized_drug_name": medication.normalized_drug_name,
        "source_type": medication.source_type,
        "source_document_id": medication.source_document_id,
        "created_at": _iso(medication.created_at),
        "updated_at": _iso(medication.updated_at),
    }


def event_data(event: MedicationEvent) -> dict[str, Any]:
    return {
        "id": event.id,
        "medication_id": event.medication_id,
        "event_type": event.event_type,
        "event_date": _iso(event.event_date),
        "old_instruction": json.loads(event.old_instruction_json)
        if event.old_instruction_json
        else None,
        "new_instruction": json.loads(event.new_instruction_json)
        if event.new_instruction_json
        else None,
        "source_document_id": event.source_document_id,
        "stop_source": event.stop_source,
        "note": event.note,
        "confirmed_at": _iso(event.confirmed_at),
    }


def daily_data(record: MedicationDaily) -> dict[str, Any]:
    return {
        "id": record.id,
        "medication_id": record.medication_id,
        "record_date": _iso(record.record_date),
        "intake_status": record.intake_status,
        "actual_dosage": record.actual_dosage,
        "actual_dosage_unit": record.actual_dosage_unit,
        "note": record.note,
        "recorded_at": _iso(record.recorded_at),
    }


def weight_data(record: WeightRecord) -> dict[str, Any]:
    return {
        "id": record.id,
        "measured_at": _iso(record.measured_at),
        "weight_kg": record.weight_kg,
        "source_type": record.source_type,
        "note": record.note,
        "created_at": _iso(record.created_at),
    }


class HealthRecordService:
    def __init__(self, session: Session, account: UserAccount) -> None:
        self.session = session
        self.account = account

    def profile(self) -> PatientProfile:
        profile = self.session.scalar(
            select(PatientProfile).where(PatientProfile.account_uid == self.account.uid)
        )
        if profile is None:
            profile = PatientProfile(account_uid=self.account.uid)
            self.session.add(profile)
            self.session.commit()
            self.session.refresh(profile)
        return profile

    def latest_cycle_start(self, patient_id: str) -> date | None:
        return self.session.scalar(
            select(MenstrualCycle.start_date)
            .where(MenstrualCycle.patient_id == patient_id)
            .order_by(MenstrualCycle.start_date.desc())
            .limit(1)
        )

    def update_profile(self, payload: PatientProfileUpdate) -> PatientProfile:
        profile = self.profile()
        if payload.updated_at is not None and payload.updated_at != profile.updated_at:
            raise BusinessError("RESOURCE_VERSION_CONFLICT", "The profile has changed.", 409)

        values = payload.model_dump(
            exclude_unset=True,
            exclude={
                "accept_external_ocr_notice",
                "complete_onboarding",
                "last_menstrual_start_date",
                "updated_at",
            },
        )
        for field, value in values.items():
            setattr(profile, field, value)

        if payload.accept_external_ocr_notice:
            profile.external_ocr_notice_version = "p0-v1"
            profile.external_ocr_notice_accepted_at = utc_now()

        if payload.last_menstrual_start_date is not None:
            existing = self.session.scalar(
                select(MenstrualCycle).where(
                    MenstrualCycle.patient_id == profile.patient_id,
                    MenstrualCycle.start_date == payload.last_menstrual_start_date,
                )
            )
            if existing is None:
                self.session.add(
                    MenstrualCycle(
                        patient_id=profile.patient_id,
                        start_date=payload.last_menstrual_start_date,
                        source_type="manual",
                    )
                )

        profile.onboarding_step = self._onboarding_step(profile)
        if payload.complete_onboarding:
            missing = self._missing_onboarding_fields(profile)
            if missing:
                raise BusinessError(
                    "VALIDATION_ERROR",
                    "Required onboarding fields are missing.",
                    422,
                    details={"fields": missing},
                )
            profile.onboarding_completed = True
            profile.onboarding_step = 4
            self.account.onboarding_completed = True

        profile.updated_at = utc_now()
        self.session.commit()
        self.session.refresh(profile)
        return profile

    @staticmethod
    def _missing_onboarding_fields(profile: PatientProfile) -> list[str]:
        fields = (
            "nickname",
            "birth_date",
            "height_cm",
            "diagnosis_year",
            "usual_cycle_length_days",
            "health_goal",
        )
        return [field for field in fields if getattr(profile, field) is None]

    @staticmethod
    def _onboarding_step(profile: PatientProfile) -> int:
        if profile.onboarding_completed:
            return 4
        if profile.nickname is None or profile.birth_date is None:
            return 0
        if profile.height_cm is None or profile.diagnosis_year is None:
            return 1
        if profile.usual_cycle_length_days is None:
            return 2
        if profile.health_goal is None:
            return 3
        return 4

    def medications(self, status: str | None, limit: int, cursor: str | None) -> list[Medication]:
        statement = select(Medication).where(Medication.patient_id == self.profile().patient_id)
        if status is not None:
            statement = statement.where(Medication.current_status == status)
        if cursor is not None:
            try:
                cursor_time = datetime.fromisoformat(cursor)
            except ValueError as exc:
                raise BusinessError("VALIDATION_ERROR", "Invalid cursor.", 422) from exc
            statement = statement.where(Medication.created_at < cursor_time)
        return list(
            self.session.scalars(statement.order_by(Medication.created_at.desc()).limit(limit + 1))
        )

    def create_medication(
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
                .order_by(MedicationEvent.event_date, MedicationEvent.id)
                .limit(1)
            )
            if event is None:
                raise BusinessError("RESOURCE_NOT_FOUND", "Medication event was not found.", 404)
            return existing, event
        medication = Medication(
            patient_id=profile.patient_id,
            drug_name=payload.drug_name.strip(),
            normalized_drug_name=payload.drug_name.strip().casefold(),
            specification=payload.specification,
            dosage_text=payload.dosage_text,
            dosage_value=payload.dosage_value,
            dosage_unit=payload.dosage_unit,
            frequency=payload.frequency,
            route=payload.route,
            start_date=payload.start_date,
            current_status="active",
            source_type=payload.source_type,
            source_document_id=payload.source_document_id,
            idempotency_key=idempotency_key,
        )
        self.session.add(medication)
        self.session.flush()
        event = MedicationEvent(
            patient_id=profile.patient_id,
            medication_id=medication.id,
            event_type="started",
            event_date=payload.event_date,
            new_instruction_json=json.dumps(_instruction(medication), ensure_ascii=False),
            source_document_id=payload.source_document_id,
            confirmed_by_uid=self.account.uid,
            confirmed_at=utc_now(),
            note=payload.note,
        )
        self.session.add(event)
        self.session.commit()
        self.session.refresh(medication)
        self.session.refresh(event)
        return medication, event

    def owned_medication(self, medication_id: str) -> Medication:
        medication = self.session.scalar(
            select(Medication).where(
                Medication.id == medication_id,
                Medication.patient_id == self.profile().patient_id,
            )
        )
        if medication is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Medication was not found.", 404)
        return medication

    def update_medication(
        self, medication_id: str, payload: MedicationUpdate
    ) -> tuple[Medication, MedicationEvent]:
        medication = self.owned_medication(medication_id)
        if payload.updated_at != medication.updated_at:
            raise BusinessError("RESOURCE_VERSION_CONFLICT", "The medication has changed.", 409)
        old_instruction = _instruction(medication)
        for field in (
            "drug_name",
            "specification",
            "dosage_text",
            "dosage_value",
            "dosage_unit",
            "frequency",
            "route",
            "end_date",
            "current_status",
        ):
            if field in payload.model_fields_set:
                setattr(medication, field, getattr(payload, field))
        if payload.drug_name is not None:
            medication.normalized_drug_name = payload.drug_name.strip().casefold()
        if payload.event_type == "stopped":
            medication.current_status = "stopped"
            medication.end_date = payload.end_date or payload.event_date
        medication.updated_at = utc_now()
        event = MedicationEvent(
            patient_id=medication.patient_id,
            medication_id=medication.id,
            event_type=payload.event_type,
            event_date=payload.event_date,
            old_instruction_json=json.dumps(old_instruction, ensure_ascii=False),
            new_instruction_json=json.dumps(_instruction(medication), ensure_ascii=False),
            confirmed_by_uid=self.account.uid,
            confirmed_at=utc_now(),
            stop_source=payload.stop_source,
            note=payload.note or payload.change_reason,
        )
        self.session.add(event)
        self.session.commit()
        self.session.refresh(medication)
        self.session.refresh(event)
        return medication, event

    def medication_events(self, medication_id: str) -> list[MedicationEvent]:
        medication = self.owned_medication(medication_id)
        return list(
            self.session.scalars(
                select(MedicationEvent)
                .where(MedicationEvent.medication_id == medication.id)
                .order_by(MedicationEvent.event_date.desc())
            )
        )

    def set_daily_status(
        self, medication_id: str, payload: MedicationDailyUpsert
    ) -> MedicationDaily:
        medication = self.owned_medication(medication_id)
        record = self.session.scalar(
            select(MedicationDaily).where(
                MedicationDaily.medication_id == medication.id,
                MedicationDaily.record_date == payload.record_date,
            )
        )
        if record is None:
            record = MedicationDaily(
                patient_id=medication.patient_id,
                medication_id=medication.id,
                record_date=payload.record_date,
                intake_status=payload.intake_status,
                recorded_by_uid=self.account.uid,
            )
            self.session.add(record)
        record.intake_status = payload.intake_status
        record.actual_dosage = payload.actual_dosage
        record.actual_dosage_unit = payload.actual_dosage_unit
        record.note = payload.note
        record.recorded_at = utc_now()
        self.session.commit()
        self.session.refresh(record)
        return record

    def daily_range(
        self, from_date: date, to_date: date, medication_id: str | None = None
    ) -> tuple[list[MedicationDaily], dict[str, int]]:
        if to_date < from_date or (to_date - from_date).days > 366:
            raise BusinessError("VALIDATION_ERROR", "Invalid date range.", 422)
        profile = self.profile()
        statement = select(MedicationDaily).where(
            MedicationDaily.patient_id == profile.patient_id,
            MedicationDaily.record_date >= from_date,
            MedicationDaily.record_date <= to_date,
        )
        if medication_id is not None:
            self.owned_medication(medication_id)
            statement = statement.where(MedicationDaily.medication_id == medication_id)
        records = list(
            self.session.scalars(
                statement.order_by(MedicationDaily.record_date, MedicationDaily.medication_id)
            )
        )
        counts = {"taken": 0, "missed": 0, "unrecorded": 0}
        for record in records:
            counts[record.intake_status] += 1
        medication_statement = select(Medication).where(
            Medication.patient_id == profile.patient_id,
            (Medication.start_date.is_(None) | (Medication.start_date <= to_date)),
            (Medication.end_date.is_(None) | (Medication.end_date >= from_date)),
        )
        if medication_id is not None:
            medication_statement = medication_statement.where(Medication.id == medication_id)
        expected = 0
        for medication in self.session.scalars(medication_statement):
            first_day = max(from_date, medication.start_date or from_date)
            last_day = min(to_date, medication.end_date or to_date)
            expected += max(0, (last_day - first_day).days + 1)
        counts["unrecorded"] += max(0, expected - len(records))
        return records, counts

    def cycles(
        self, from_date: date | None = None, to_date: date | None = None
    ) -> list[MenstrualCycle]:
        statement = select(MenstrualCycle).where(
            MenstrualCycle.patient_id == self.profile().patient_id
        )
        if from_date is not None:
            statement = statement.where(MenstrualCycle.start_date >= from_date)
        if to_date is not None:
            statement = statement.where(MenstrualCycle.start_date <= to_date)
        return list(self.session.scalars(statement.order_by(MenstrualCycle.start_date.desc())))

    def save_cycle(self, payload: CycleInput, cycle_id: str | None = None) -> MenstrualCycle:
        profile = self.profile()
        cycle = None
        if cycle_id is not None:
            cycle = self.session.scalar(
                select(MenstrualCycle).where(
                    MenstrualCycle.id == cycle_id,
                    MenstrualCycle.patient_id == profile.patient_id,
                )
            )
            if cycle is None:
                raise BusinessError("RESOURCE_NOT_FOUND", "Cycle was not found.", 404)
            if payload.updated_at is not None and payload.updated_at != cycle.updated_at:
                raise BusinessError("RESOURCE_VERSION_CONFLICT", "The cycle has changed.", 409)

        new_end = payload.end_date or payload.start_date
        overlaps = self.session.scalars(
            select(MenstrualCycle).where(
                MenstrualCycle.patient_id == profile.patient_id,
                MenstrualCycle.start_date <= new_end,
            )
        )
        for existing in overlaps:
            existing_end = existing.end_date or existing.start_date
            if existing.id != cycle_id and payload.start_date <= existing_end:
                raise BusinessError("CYCLE_DATE_OVERLAP", "Cycle dates overlap.", 409)

        if cycle is None:
            cycle = MenstrualCycle(patient_id=profile.patient_id, start_date=payload.start_date)
            self.session.add(cycle)
        cycle.start_date = payload.start_date
        cycle.end_date = payload.end_date
        cycle.flow_level = payload.flow_level
        cycle.note = payload.note
        cycle.source_type = payload.source_type
        cycle.updated_at = utc_now()
        self.session.commit()
        self.session.refresh(cycle)
        return cycle

    def cycle_data(self, cycle: MenstrualCycle) -> dict[str, Any]:
        previous_start = self.session.scalar(
            select(func.max(MenstrualCycle.start_date)).where(
                MenstrualCycle.patient_id == cycle.patient_id,
                MenstrualCycle.start_date < cycle.start_date,
            )
        )
        return {
            "id": cycle.id,
            "start_date": _iso(cycle.start_date),
            "end_date": _iso(cycle.end_date),
            "flow_level": cycle.flow_level,
            "note": cycle.note,
            "source_type": cycle.source_type,
            "updated_at": _iso(cycle.updated_at),
            "cycle_length_days": (cycle.start_date - previous_start).days
            if previous_start
            else None,
            "duration_days": (cycle.end_date - cycle.start_date).days + 1
            if cycle.end_date
            else None,
            "created_at": _iso(cycle.created_at),
        }

    def weights(
        self, from_date: date | None = None, to_date: date | None = None
    ) -> list[WeightRecord]:
        statement = select(WeightRecord).where(WeightRecord.patient_id == self.profile().patient_id)
        if from_date is not None:
            statement = statement.where(WeightRecord.record_date >= from_date)
        if to_date is not None:
            statement = statement.where(WeightRecord.record_date <= to_date)
        return list(self.session.scalars(statement.order_by(WeightRecord.measured_at.desc())))

    def save_weight(
        self, payload: WeightInput, weight_id: str | None = None
    ) -> tuple[WeightRecord, bool]:
        if payload.measured_at.tzinfo is None:
            raise BusinessError("VALIDATION_ERROR", "measured_at must include a timezone.", 422)
        profile = self.profile()
        record_date = payload.measured_at.astimezone(UTC).date()
        if weight_id is None:
            record = self.session.scalar(
                select(WeightRecord).where(
                    WeightRecord.patient_id == profile.patient_id,
                    WeightRecord.record_date == record_date,
                )
            )
        else:
            record = self.session.scalar(
                select(WeightRecord).where(
                    WeightRecord.id == weight_id,
                    WeightRecord.patient_id == profile.patient_id,
                )
            )
            if record is None:
                raise BusinessError("RESOURCE_NOT_FOUND", "Weight was not found.", 404)
        created = record is None
        if created:
            record = WeightRecord(
                patient_id=profile.patient_id,
                measured_at=payload.measured_at,
                record_date=record_date,
                weight_kg=payload.weight_kg,
            )
            self.session.add(record)
        record.measured_at = payload.measured_at
        record.record_date = record_date
        record.weight_kg = payload.weight_kg
        record.source_type = payload.source_type
        record.note = payload.note
        record.updated_at = utc_now()
        self.session.commit()
        self.session.refresh(record)
        return record, created

    def dashboard(self, target_date: date) -> dict[str, Any]:
        profile = self.profile()
        latest_report = self.session.scalar(
            select(ReportSnapshot)
            .where(ReportSnapshot.patient_id == profile.patient_id)
            .order_by(ReportSnapshot.generated_at.desc())
            .limit(1)
        )
        medications = list(
            self.session.scalars(
                select(Medication).where(
                    Medication.patient_id == profile.patient_id,
                    Medication.current_status == "active",
                )
            )
        )
        today_records = {
            row.medication_id: row
            for row in self.session.scalars(
                select(MedicationDaily).where(
                    MedicationDaily.patient_id == profile.patient_id,
                    MedicationDaily.record_date == target_date,
                )
            )
        }
        month_start = target_date.replace(day=1)
        _, month_counts = self.daily_range(month_start, target_date)
        by_medication: list[dict[str, Any]] = []
        for medication in medications:
            _, counts = self.daily_range(month_start, target_date, medication.id)
            by_medication.append(
                {
                    "medication_id": medication.id,
                    "drug_name": medication.drug_name,
                    "taken_count": counts["taken"],
                    "missed_count": counts["missed"],
                    "unrecorded_count": counts["unrecorded"],
                }
            )
        return {
            "server_date": target_date.isoformat(),
            "data_as_of": utc_now().isoformat(),
            "profile_summary": {
                "patient_id": profile.patient_id,
                "nickname": profile.nickname,
                "primary_condition": profile.primary_condition,
            },
            "next_visit": {
                "date": profile.next_visit_date.isoformat(),
                "days_remaining": (profile.next_visit_date - target_date).days,
            }
            if profile.next_visit_date
            else None,
            "today_medications": [
                {
                    "medication_id": medication.id,
                    "drug_name": medication.drug_name,
                    "specification": medication.specification,
                    "dosage_text": medication.dosage_text,
                    "frequency": medication.frequency,
                    "intake_status": today_records.get(medication.id, None).intake_status
                    if medication.id in today_records
                    else "unrecorded",
                    "recorded_at": _iso(today_records[medication.id].recorded_at)
                    if medication.id in today_records
                    else None,
                }
                for medication in medications
            ],
            "month_medication_stats": {
                "month": target_date.strftime("%Y-%m"),
                "taken_count": month_counts["taken"],
                "missed_count": month_counts["missed"],
                "unrecorded_count": month_counts["unrecorded"],
                "by_medication": by_medication,
            },
            "latest_report": {
                "report_id": latest_report.id,
                "status": latest_report.status,
                "generated_at": latest_report.generated_at.isoformat(),
                "snapshot_hash": latest_report.snapshot_hash,
                "failure_reason": latest_report.failure_reason,
            }
            if latest_report
            else None,
        }
