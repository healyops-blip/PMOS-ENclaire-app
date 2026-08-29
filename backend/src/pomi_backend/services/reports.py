"""Deterministic, patient-scoped immutable report snapshot generation."""

from __future__ import annotations

import hashlib
import json
from calendar import monthrange
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any
from uuid import NAMESPACE_URL, uuid5

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    DocumentDisplayAsset,
    ImagingReport,
    LabObservation,
    MedicalOrder,
    Medication,
    MedicationDaily,
    MedicationEvent,
    MenstrualCycle,
    OutpatientRecord,
    PatientNote,
    ReportSnapshot,
    ReportSource,
    UserAccount,
    WeightRecord,
)
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import (
    PatientNoteRepository,
    PatientRepository,
    ReportSnapshotRepository,
    ReportSourceRepository,
)
from pomi_backend.schemas.reports import ReportCreate
from pomi_backend.services.watermarks import (
    ASSET_TYPE,
    WATERMARK_VERSION,
    display_asset_data,
)

RULE_VERSION = "report-rules-v2"
TEMPLATE_VERSION = "report-snapshot-v2"
CANONICAL_TREND_UNITS = {
    "glucose": "mmol/L",
    "total_cholesterol": "mmol/L",
    "total_testosterone": "nmol/L",
    "testosterone": "nmol/L",
}
BMI_REFERENCE_LOWER = 18.5
BMI_REFERENCE_UPPER = 24.0
DISCLAIMER = [
    "模拟数据，仅供演示。",
    "患者自述仅供参考，不构成诊断，不进入正式病历。",
    "本报告仅整理已确认数据，不提供病情、因果或用药调整结论。",
]


def _json_value(value: Any) -> Any:
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    return value


def _stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _digest(value: Any) -> str:
    return hashlib.sha256(_stable_json(value).encode()).hexdigest()


def _freshness(value: date, as_of: date) -> str:
    if value >= _months_before(as_of, 3):
        return "current"
    if value >= _months_before(as_of, 6):
        return "caution"
    if value >= _months_before(as_of, 12):
        return "stale"
    return "archived"


def _months_before(value: date, months: int) -> date:
    month_index = value.year * 12 + value.month - 1 - months
    year, zero_based_month = divmod(month_index, 12)
    month = zero_based_month + 1
    return date(year, month, min(value.day, monthrange(year, month)[1]))


@dataclass(frozen=True)
class _SourceDraft:
    source_type: str
    source_record_id: str
    origin_kind: str
    document_id: str | None = None
    document_revision_id: str | None = None
    rule_execution_id: str | None = None


class ReportSnapshotService:
    def __init__(
        self,
        session: Session,
        account: UserAccount,
        business_date: date,
    ) -> None:
        self.session = session
        self.account = account
        self.business_date = business_date
        self.profile = PatientRepository(session).get_or_create(account.uid)
        self.notes = PatientNoteRepository(session, self.profile.patient_id)
        self.reports = ReportSnapshotRepository(session, self.profile.patient_id)
        self.sources = ReportSourceRepository(session, self.reports)

    def create(self, payload: ReportCreate) -> tuple[dict[str, Any], bool]:
        sections = sorted(set(payload.include_sections))
        note = self._selected_note(payload.patient_note_id)
        state, missing, source_drafts = self._collect(note, sections)
        if missing and not payload.confirm_incomplete:
            raise BusinessError(
                "REPORT_INCOMPLETE_CONFIRMATION_REQUIRED",
                "Confirm the missing sections before generating the report.",
                409,
                details={"missing_sections": missing},
            )

        source_digest = self._source_digest(state, sections, source_drafts)
        existing = self.reports.find_by_source_digest(source_digest)
        if existing is not None and existing.report_status == "succeeded":
            return self._detail(existing, has_updates=False, reused=True), True

        previous = self.reports.latest_succeeded()
        generated_at = datetime.now(UTC)
        rule_execution_id = str(uuid5(NAMESPACE_URL, f"pomi:{source_digest}:{RULE_VERSION}"))
        source_drafts.append(
            _SourceDraft(
                "rule_execution",
                rule_execution_id,
                "rule_execution",
                rule_execution_id=rule_execution_id,
            )
        )
        report = ReportSnapshot(
            patient_id=self.profile.patient_id,
            patient_note_id=note.id if note else None,
            previous_report_id=previous.id if previous else None,
            report_status="pending",
            source_digest=source_digest,
            generated_by_uid=self.account.uid,
        )
        try:
            self.reports.add(report)
            source_nodes = self._persist_sources(report, source_drafts)
            snapshot, date_sources, freshness = self._build_snapshot(
                state,
                sections,
                missing,
                source_nodes,
                generated_at,
            )
            report.snapshot_json = snapshot
            report.date_source_json = date_sources
            report.freshness_result_json = freshness
            report.snapshot_hash = _digest(snapshot)
            report.report_generated_at = generated_at
            report.report_status = "succeeded"
            if note is not None:
                note.status = "consumed"
                note.consumed_at = generated_at
            self.session.commit()
            self.session.refresh(report)
        except IntegrityError:
            self.session.rollback()
            existing = self.reports.find_by_source_digest(source_digest)
            if existing is not None and existing.report_status == "succeeded":
                return self._detail(existing, has_updates=False, reused=True), True
            raise
        except Exception:
            self.session.rollback()
            raise
        return self._detail(report, has_updates=False, reused=False), False

    def list(self) -> list[dict[str, Any]]:
        eligible = self._latest_eligible_note()
        items: list[dict[str, Any]] = []
        for report in self.reports.list_succeeded():
            snapshot = report.snapshot_json or {}
            sections = list(snapshot.get("metadata", {}).get("include_sections", []))
            state, _, source_drafts = self._collect(eligible, sections)
            current_digest = self._source_digest(state, sections, source_drafts)
            items.append(
                self._list_item(
                    report,
                    has_updates=current_digest != report.source_digest,
                    reused=False,
                )
            )
        return items

    def get(self, report_id: str) -> dict[str, Any]:
        report = self.reports.get(report_id)
        if report is None or report.report_status != "succeeded":
            raise BusinessError("RESOURCE_NOT_FOUND", "Report was not found.", 404)
        snapshot = report.snapshot_json or {}
        sections = list(snapshot.get("metadata", {}).get("include_sections", []))
        eligible = self._latest_eligible_note()
        state, _, source_drafts = self._collect(eligible, sections)
        current_digest = self._source_digest(state, sections, source_drafts)
        return self._detail(
            report,
            has_updates=current_digest != report.source_digest,
            reused=False,
        )

    def preflight(self, payload: ReportCreate) -> dict[str, Any]:
        sections = sorted(set(payload.include_sections))
        note = self._selected_note(payload.patient_note_id)
        _, missing, source_drafts = self._collect(note, sections)
        return {
            "missing_sections": missing,
            "can_generate": not missing or payload.confirm_incomplete,
            "confirmed_source_count": len(source_drafts),
        }

    def _selected_note(self, note_id: str | None) -> PatientNote | None:
        note = self.notes.get(note_id) if note_id else self._latest_eligible_note()
        if note_id and note is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Patient note was not found.", 404)
        if note is not None and note.status not in {"confirmed", "skipped", "consumed"}:
            raise BusinessError(
                "PATIENT_NOTE_NOT_CONFIRMED",
                "Confirm or explicitly skip the patient statement first.",
                409,
            )
        return note

    def _latest_eligible_note(self) -> PatientNote | None:
        return self.session.scalar(
            select(PatientNote)
            .where(
                PatientNote.patient_id == self.profile.patient_id,
                PatientNote.status.in_(["confirmed", "skipped", "consumed"]),
            )
            .order_by(PatientNote.created_at.desc())
            .limit(1)
        )

    def _collect(
        self,
        note: PatientNote | None,
        sections: list[str],
    ) -> tuple[dict[str, Any], list[str], list[_SourceDraft]]:
        patient_id = self.profile.patient_id
        medications = list(
            self.session.scalars(
                select(Medication)
                .where(Medication.patient_id == patient_id)
                .order_by(Medication.created_at, Medication.id)
            )
        )
        medication_events = list(
            self.session.scalars(
                select(MedicationEvent)
                .where(MedicationEvent.patient_id == patient_id)
                .order_by(MedicationEvent.event_date, MedicationEvent.id)
            )
        )
        medication_daily = list(
            self.session.scalars(
                select(MedicationDaily)
                .where(MedicationDaily.patient_id == patient_id)
                .order_by(MedicationDaily.record_date, MedicationDaily.id)
            )
        )
        cycles = list(
            self.session.scalars(
                select(MenstrualCycle)
                .where(
                    MenstrualCycle.patient_id == patient_id,
                    MenstrualCycle.deleted_at.is_(None),
                )
                .order_by(MenstrualCycle.start_date, MenstrualCycle.id)
            )
        )
        weights = list(
            self.session.scalars(
                select(WeightRecord)
                .where(WeightRecord.patient_id == patient_id)
                .order_by(WeightRecord.record_date, WeightRecord.id)
            )
        )
        labs = list(
            self.session.scalars(
                select(LabObservation)
                .where(
                    LabObservation.patient_id == patient_id,
                    LabObservation.confirmed_by_uid == self.account.uid,
                )
                .order_by(LabObservation.trend_date, LabObservation.item_index, LabObservation.id)
            )
        )
        medical_orders = list(
            self.session.scalars(
                select(MedicalOrder)
                .where(
                    MedicalOrder.patient_id == patient_id,
                    MedicalOrder.confirmed_by_uid == self.account.uid,
                )
                .order_by(MedicalOrder.order_date, MedicalOrder.medication_index, MedicalOrder.id)
            )
        )
        imaging = list(
            self.session.scalars(
                select(ImagingReport)
                .where(
                    ImagingReport.patient_id == patient_id,
                    ImagingReport.confirmed_by_uid == self.account.uid,
                )
                .order_by(
                    ImagingReport.examined_at,
                    ImagingReport.reported_at,
                    ImagingReport.id,
                )
            )
        )
        outpatient = list(
            self.session.scalars(
                select(OutpatientRecord)
                .where(
                    OutpatientRecord.patient_id == patient_id,
                    OutpatientRecord.confirmed_by_uid == self.account.uid,
                )
                .order_by(OutpatientRecord.visit_date, OutpatientRecord.id)
            )
        )

        profile_data = {
            "patient_id": self.profile.patient_id,
            "nickname": self.profile.nickname,
            "birth_date": _json_value(self.profile.birth_date),
            "gender": self.profile.gender,
            "height_cm": _json_value(self.profile.height_cm),
            "diagnosis_year": self.profile.diagnosis_year,
            "period_duration_days": self.profile.period_duration_days,
            "primary_condition": self.profile.primary_condition,
            "next_visit_date": _json_value(self.profile.next_visit_date),
            "health_goal": self.profile.health_goal,
        }
        note_data = None
        if note is not None:
            note_data = {
                "id": note.id,
                "text": note.confirmed_text,
                "explicitly_skipped": note.confirmed_text is None,
                "confirmed_at": _json_value(note.confirmed_at),
            }
        state = {
            "profile": profile_data,
            "patient_note": note_data,
            "collections": {
                "medications": [self._medication_data(item) for item in medications],
                "medication_events": [
                    self._medication_event_data(item) for item in medication_events
                ],
                "medication_daily": [
                    self._medication_daily_data(item) for item in medication_daily
                ],
                "cycles": [self._cycle_data(item) for item in cycles],
                "weights": [self._weight_data(item) for item in weights],
                "labs": [self._lab_data(item) for item in labs],
                "medical_orders": [self._medical_order_data(item) for item in medical_orders],
                "imaging": [self._imaging_data(item) for item in imaging],
                "outpatient": [self._outpatient_data(item) for item in outpatient],
            },
        }
        missing: list[str] = []
        if "profile" in sections and not self.profile.onboarding_completed:
            missing.append("profile")
        if "patient_note" in sections and note is None:
            missing.append("patient_note")
        for section in ("medications", "labs", "imaging", "outpatient", "cycles", "weights"):
            if section in sections and not state["collections"][section]:
                missing.append(section)

        source_drafts: list[_SourceDraft] = []
        if "profile" in sections:
            source_drafts.append(
                _SourceDraft("patient_profile", self.profile.patient_id, "system_record")
            )
        if "patient_note" in sections and note is not None:
            source_drafts.append(_SourceDraft("patient_note", note.id, "patient_manual"))
        order_revision_by_document = {
            item.document_id: item.document_revision_id for item in medical_orders
        }
        if "medications" in sections:
            source_drafts.extend(
                _SourceDraft("medication", item.id, "system_record") for item in medications
            )
            source_drafts.extend(
                _SourceDraft(
                    "medication_event",
                    item.id,
                    "medical_document"
                    if item.source_document_id in order_revision_by_document
                    else "system_record",
                    document_id=item.source_document_id
                    if item.source_document_id in order_revision_by_document
                    else None,
                    document_revision_id=order_revision_by_document.get(item.source_document_id),
                )
                for item in medication_events
            )
            source_drafts.extend(
                _SourceDraft("medication_daily", item.id, "patient_manual")
                for item in medication_daily
            )
            source_drafts.extend(
                _SourceDraft(
                    "medical_order",
                    item.id,
                    "medical_document",
                    document_id=item.document_id,
                    document_revision_id=item.document_revision_id,
                )
                for item in medical_orders
            )
        if "cycles" in sections:
            source_drafts.extend(
                _SourceDraft("menstrual_cycle", item.id, "patient_manual") for item in cycles
            )
        if "weights" in sections:
            source_drafts.extend(
                _SourceDraft("weight_record", item.id, "patient_manual") for item in weights
            )
        if "labs" in sections:
            source_drafts.extend(
                _SourceDraft(
                    "lab_observation",
                    item.id,
                    "medical_document",
                    document_id=item.document_id,
                    document_revision_id=item.document_revision_id,
                )
                for item in labs
            )
        if "imaging" in sections:
            source_drafts.extend(
                _SourceDraft(
                    "imaging_report",
                    item.id,
                    "medical_document",
                    document_id=item.document_id,
                    document_revision_id=item.document_revision_id,
                )
                for item in imaging
            )
        if "outpatient" in sections:
            source_drafts.extend(
                _SourceDraft(
                    "outpatient_record",
                    item.id,
                    "medical_document",
                    document_id=item.document_id,
                    document_revision_id=item.document_revision_id,
                )
                for item in outpatient
            )
        return state, missing, source_drafts

    def _source_digest(
        self,
        state: dict[str, Any],
        sections: list[str],
        source_drafts: list[_SourceDraft],
    ) -> str:
        selected = {
            "profile": state["profile"] if "profile" in sections else None,
            "patient_note": state["patient_note"] if "patient_note" in sections else None,
            "collections": {
                key: value
                for key, value in state["collections"].items()
                if key in sections
                or key in {"medication_events", "medication_daily", "medical_orders"}
                and "medications" in sections
            },
            "include_sections": sections,
            "sources": [
                {
                    "source_type": item.source_type,
                    "source_record_id": item.source_record_id,
                    "origin_kind": item.origin_kind,
                    "document_id": item.document_id,
                    "document_revision_id": item.document_revision_id,
                    "display_asset": self._display_asset_identity(
                        item.document_id,
                        item.document_revision_id,
                    ),
                }
                for item in source_drafts
            ],
            "rule_version": RULE_VERSION,
            "template_version": TEMPLATE_VERSION,
        }
        return _digest(selected)

    def _persist_sources(
        self, report: ReportSnapshot, drafts: list[_SourceDraft]
    ) -> list[dict[str, Any]]:
        nodes: list[dict[str, Any]] = []
        for number, draft in enumerate(drafts, start=1):
            display_asset = self._display_asset(
                draft.document_id,
                draft.document_revision_id,
            )
            source = ReportSource(
                id=new_uuid(),
                report_id=report.id,
                source_type=draft.source_type,
                source_record_id=draft.source_record_id,
                origin_kind=draft.origin_kind,
                document_id=draft.document_id,
                document_revision_id=draft.document_revision_id,
                rule_execution_id=draft.rule_execution_id,
            )
            self.sources.add(source)
            nodes.append(
                {
                    "node_id": source.id,
                    "source_number": number,
                    "source_type": source.source_type,
                    "source_record_id": source.source_record_id,
                    "origin_kind": source.origin_kind,
                    "document_id": source.document_id,
                    "document_revision_id": source.document_revision_id,
                    "display_asset": display_asset_data(display_asset),
                    "rule_execution_id": source.rule_execution_id,
                }
            )
        return nodes

    def _display_asset(
        self,
        document_id: str | None,
        revision_id: str | None,
    ) -> DocumentDisplayAsset | None:
        if document_id is None or revision_id is None:
            return None
        return self.session.scalar(
            select(DocumentDisplayAsset).where(
                DocumentDisplayAsset.document_id == document_id,
                DocumentDisplayAsset.document_revision_id == revision_id,
                DocumentDisplayAsset.asset_type == ASSET_TYPE,
                DocumentDisplayAsset.watermark_version == WATERMARK_VERSION,
            )
        )

    def _display_asset_identity(
        self,
        document_id: str | None,
        revision_id: str | None,
    ) -> dict[str, Any] | None:
        asset = self._display_asset(document_id, revision_id)
        if asset is None:
            return None
        return {
            "asset_type": asset.asset_type,
            "watermark_version": asset.watermark_version,
            "status": asset.status,
            "file_hash": asset.file_hash,
        }

    def _build_snapshot(
        self,
        state: dict[str, Any],
        sections: list[str],
        missing: list[str],
        source_nodes: list[dict[str, Any]],
        generated_at: datetime,
    ) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
        collections = state["collections"]
        source_by_record = {item["source_record_id"]: item for item in source_nodes}
        rule_source = next(
            (item for item in source_nodes if item["source_type"] == "rule_execution"),
            None,
        )
        date_sources: dict[str, Any] = {}
        freshness: dict[str, Any] = {}

        def dated_point(item: dict[str, Any], date_field: str, date_source: str) -> dict[str, Any]:
            record_date = date.fromisoformat(item[date_field])
            source = source_by_record[item["id"]]
            level = _freshness(record_date, self.business_date)
            date_sources[source["node_id"]] = date_source
            freshness[source["node_id"]] = level
            return {
                **item,
                "node_id": source["node_id"],
                "source_number": source["source_number"],
                "date": item[date_field],
                "date_source": date_source,
                "freshness": level,
                "default_collapsed": level == "archived",
            }

        weights = [
            dated_point(item, "record_date", "record_date")
            for item in collections["weights"]
            if "weights" in sections
        ]
        height_cm = state["profile"].get("height_cm")
        if height_cm:
            height_m = float(height_cm) / 100
            for point in weights:
                bmi = round(float(point["weight_kg"]) / (height_m * height_m), 1)
                point.update(
                    {
                        "bmi": bmi,
                        "bmi_reference_lower": BMI_REFERENCE_LOWER,
                        "bmi_reference_upper": BMI_REFERENCE_UPPER,
                        "bmi_status": (
                            "low"
                            if bmi < BMI_REFERENCE_LOWER
                            else "in_range"
                            if bmi <= BMI_REFERENCE_UPPER
                            else "high"
                        ),
                    }
                )
        cycles = [
            dated_point(item, "start_date", "record_date")
            for item in collections["cycles"]
            if "cycles" in sections
        ]
        for index, point in enumerate(cycles):
            start = date.fromisoformat(point["start_date"])
            period_end = date.fromisoformat(point["end_date"]) if point["end_date"] else None
            next_start = (
                date.fromisoformat(cycles[index + 1]["start_date"])
                if index + 1 < len(cycles)
                else None
            )
            point["duration_days"] = (
                (period_end - start).days + 1 if period_end is not None else None
            )
            point["cycle_length_days"] = (
                (next_start - start).days if next_start is not None else None
            )
            point["cycle_end_date"] = (
                (next_start - timedelta(days=1)).isoformat() if next_start is not None else None
            )
        daily = [
            dated_point(item, "record_date", "record_date")
            for item in collections["medication_daily"]
            if "medications" in sections
        ]

        def sourced_record(item: dict[str, Any]) -> dict[str, Any]:
            source = source_by_record[item["id"]]
            return {
                **item,
                "node_id": source["node_id"],
                "source_number": source["source_number"],
            }

        medication_history = (
            [sourced_record(item) for item in collections["medications"]]
            if "medications" in sections
            else []
        )
        medication_events = (
            [sourced_record(item) for item in collections["medication_events"]]
            if "medications" in sections
            else []
        )
        active_medications = [item for item in medication_history if item["status"] == "active"]
        for medication in active_medications:
            adherence_records = [
                item for item in daily if item["medication_id"] == medication["id"]
            ]
            counts = {
                status: sum(item["intake_status"] == status for item in adherence_records)
                for status in ("taken", "missed", "unrecorded")
            }
            medication["adherence"] = {
                **counts,
                "recorded_days": len(adherence_records),
                "adherence_percent": (
                    round(counts["taken"] / len(adherence_records) * 100)
                    if adherence_records
                    else None
                ),
            }
        lab_trends: list[dict[str, Any]] = []
        lab_groups: dict[str, list[dict[str, Any]]] = {}
        for item in collections["labs"] if "labs" in sections else []:
            metric_id = item["standard_metric_id"] or f"unmapped:{item['original_item_name']}"
            lab_groups.setdefault(metric_id, []).append(item)
        for metric_id, items in sorted(lab_groups.items()):
            points: list[dict[str, Any]] = []
            contexts = {
                item["sample_context"] for item in items if item["sample_context"] is not None
            }
            target_unit = CANONICAL_TREND_UNITS.get(metric_id) or next(
                (item["standard_unit"] for item in items if item["standard_unit"]), None
            )
            group_reason: str | None = None
            group_comparability = "comparable"
            for item in items:
                source = source_by_record[item["id"]]
                point_reason: str | None = None
                normalized_value = item["numeric_value"]
                normalized_unit = item["standard_unit"]
                normalized_reference_lower = item["reference_lower"]
                normalized_reference_upper = item["reference_upper"]
                if item["mapping_status"] != "mapped":
                    point_reason = "metric_needs_manual_review"
                elif item["trend_date"] is None:
                    point_reason = "missing_valid_date"
                elif date.fromisoformat(item["trend_date"]) > self.business_date:
                    point_reason = "future_date"
                elif target_unit and normalized_unit != target_unit:
                    converted = self._convert_lab_value(
                        metric_id,
                        normalized_value,
                        normalized_unit,
                        target_unit,
                    )
                    if converted is None:
                        point_reason = "unsafe_unit_conversion"
                    else:
                        normalized_value = converted
                        if normalized_reference_lower is not None:
                            normalized_reference_lower = self._convert_lab_value(
                                metric_id,
                                normalized_reference_lower,
                                normalized_unit,
                                target_unit,
                            )
                        if normalized_reference_upper is not None:
                            normalized_reference_upper = self._convert_lab_value(
                                metric_id,
                                normalized_reference_upper,
                                normalized_unit,
                                target_unit,
                            )
                        normalized_unit = target_unit
                if len(contexts) > 1:
                    point_reason = point_reason or "sample_context_mismatch"
                if point_reason:
                    group_comparability = "incomparable"
                    group_reason = group_reason or point_reason
                record_date = date.fromisoformat(item["trend_date"]) if item["trend_date"] else None
                level = _freshness(record_date, self.business_date) if record_date else "unknown"
                date_sources[source["node_id"]] = item["trend_date_source"]
                freshness[source["node_id"]] = level
                points.append(
                    {
                        **item,
                        "node_id": source["node_id"],
                        "source_number": source["source_number"],
                        "date": item["trend_date"],
                        "date_source": item["trend_date_source"],
                        "normalized_value": normalized_value,
                        "normalized_unit": normalized_unit,
                        "normalized_reference_lower": normalized_reference_lower,
                        "normalized_reference_upper": normalized_reference_upper,
                        "freshness": level,
                        "default_collapsed": level == "archived",
                        "comparability": "incomparable" if point_reason else "comparable",
                        "exclusion_reason": point_reason,
                    }
                )
            if group_comparability == "comparable" and self._hormone_context_incomplete(
                metric_id, items
            ):
                group_comparability = "caution"
                group_reason = "hormone_context_incomplete"
            comparable_count = sum(point["comparability"] == "comparable" for point in points)
            lab_trends.append(
                {
                    "metric_id": metric_id,
                    "metric_name": items[0]["original_item_name"],
                    "unit": target_unit,
                    "comparability": group_comparability,
                    "comparability_reason": group_reason,
                    "display_mode": "single_result"
                    if comparable_count <= 1
                    else "comparison"
                    if comparable_count == 2
                    else "trend",
                    "points": sorted(points, key=lambda point: point["date"] or ""),
                }
            )

        def clinical_record(
            item: dict[str, Any],
            date_fields: list[tuple[str, str]],
        ) -> dict[str, Any]:
            source = source_by_record[item["id"]]
            selected = next(
                ((item[field], source_name) for field, source_name in date_fields if item[field]),
                (None, None),
            )
            record_date = date.fromisoformat(selected[0]) if selected[0] else None
            level = _freshness(record_date, self.business_date) if record_date else "unknown"
            date_sources[source["node_id"]] = selected[1]
            freshness[source["node_id"]] = level
            return {
                **item,
                "node_id": source["node_id"],
                "source_number": source["source_number"],
                "date": selected[0],
                "date_source": selected[1],
                "freshness": level,
                "default_collapsed": level == "archived",
            }

        imaging_records = [
            clinical_record(
                item,
                [("examination_date", "exam_date"), ("report_date", "report_date")],
            )
            for item in collections["imaging"]
            if "imaging" in sections
        ]
        outpatient_records = [
            clinical_record(item, [("visit_date", "visit_date")])
            for item in collections["outpatient"]
            if "outpatient" in sections
        ]
        order_records = [
            clinical_record(item, [("order_date", "order_date")])
            for item in collections["medical_orders"]
            if "medications" in sections
        ]
        latest_observations = [
            trend["points"][-1]
            for trend in lab_trends
            if trend["points"] and trend["points"][-1]["date"] is not None
        ]
        cycle_summary = (
            {
                "count": len(cycles),
                "range_start": cycles[0]["start_date"],
                "range_end": self.business_date.isoformat(),
            }
            if cycles
            else None
        )
        latest_weight = weights[-1] if weights else None
        weight_summary = (
            {
                "count": len(weights),
                "latest_weight_kg": latest_weight["weight_kg"],
                "latest_bmi": latest_weight.get("bmi"),
                "bmi_reference_lower": latest_weight.get("bmi_reference_lower"),
                "bmi_reference_upper": latest_weight.get("bmi_reference_upper"),
                "bmi_status": latest_weight.get("bmi_status"),
            }
            if latest_weight
            else None
        )
        snapshot = {
            "metadata": {
                "rule_version": RULE_VERSION,
                "template_version": TEMPLATE_VERSION,
                "generated_at": generated_at.isoformat(),
                "include_sections": sections,
                "simulated_data": True,
                "rule_execution_node_id": rule_source["node_id"] if rule_source else None,
            },
            "summary": {
                "profile": state["profile"] if "profile" in sections else {},
                "patient_note_text": (
                    state["patient_note"]["text"]
                    if "patient_note" in sections and state["patient_note"]
                    else None
                ),
                "patient_note_empty_state": (
                    "explicitly_skipped"
                    if state["patient_note"] and state["patient_note"]["explicitly_skipped"]
                    else "missing"
                    if state["patient_note"] is None
                    else None
                ),
                "current_medications": active_medications if "medications" in sections else [],
                "latest_observations": latest_observations if "labs" in sections else [],
                "cycle_summary": cycle_summary if "cycles" in sections else None,
                "weight_summary": weight_summary if "weights" in sections else None,
                "missing_sections": missing,
                "disclaimers": DISCLAIMER,
            },
            "trends": {
                "weights": weights if "weights" in sections else [],
                "cycles": cycles if "cycles" in sections else [],
                "medication_daily": daily if "medications" in sections else [],
                "labs": lab_trends if "labs" in sections else [],
            },
            "records": {
                "medication_history": medication_history if "medications" in sections else [],
                "medication_events": medication_events if "medications" in sections else [],
                "medical_orders": order_records if "medications" in sections else [],
                "imaging": imaging_records if "imaging" in sections else [],
                "outpatient": outpatient_records if "outpatient" in sections else [],
            },
            "sources": source_nodes,
        }
        return snapshot, date_sources, freshness

    @staticmethod
    def _medication_data(item: Medication) -> dict[str, Any]:
        return {
            "id": item.id,
            "drug_name": item.drug_name,
            "source_category": item.source_category,
            "specification": item.specification,
            "dosage_value": _json_value(item.dosage_value),
            "dosage_unit": item.dosage_unit,
            "frequency": item.frequency,
            "route": item.route,
            "status": item.status,
            "start_date": _json_value(item.start_date),
            "end_date": _json_value(item.end_date),
            "replaces_medication_id": item.replaces_medication_id,
        }

    @staticmethod
    def _medication_event_data(item: MedicationEvent) -> dict[str, Any]:
        return {
            "id": item.id,
            "medication_id": item.medication_id,
            "event_type": item.event_type,
            "event_date": item.event_date.isoformat(),
            "old_instruction": item.old_instruction,
            "new_instruction": item.new_instruction,
            "source_type": item.source_type,
            "source_document_id": item.source_document_id,
        }

    @staticmethod
    def _medication_daily_data(item: MedicationDaily) -> dict[str, Any]:
        return {
            "id": item.id,
            "medication_id": item.medication_id,
            "record_date": item.record_date.isoformat(),
            "intake_status": item.intake_status,
        }

    @staticmethod
    def _cycle_data(item: MenstrualCycle) -> dict[str, Any]:
        return {
            "id": item.id,
            "start_date": item.start_date.isoformat(),
            "end_date": _json_value(item.end_date),
            "flow_level": item.flow_level,
            "note": item.note,
            "source_type": item.source_type,
        }

    @staticmethod
    def _weight_data(item: WeightRecord) -> dict[str, Any]:
        return {
            "id": item.id,
            "record_date": item.record_date.isoformat(),
            "weight_kg": _json_value(item.weight_kg),
        }

    @staticmethod
    def _lab_data(item: LabObservation) -> dict[str, Any]:
        context = item.original_item_data or {}
        return {
            "id": item.id,
            "ocr_result_id": item.ocr_result_id,
            "original_item_name": item.original_item_name,
            "standard_metric_id": item.standard_metric_id,
            "mapping_status": item.mapping_status,
            "raw_value": item.raw_value,
            "numeric_value": _json_value(item.numeric_value),
            "original_unit": item.original_unit,
            "standard_unit": item.standard_unit,
            "reference_range_raw": item.reference_range_raw,
            "reference_lower": _json_value(item.reference_lower),
            "reference_upper": _json_value(item.reference_upper),
            "abnormal_status": ReportSnapshotService._abnormal_status(item),
            "trend_date": _json_value(item.trend_date),
            "trend_date_source": item.trend_date_source,
            "facility": context.get("hospital_name") or context.get("hospital"),
            "sample_context": context.get("sample_context") or context.get("sample_type"),
            "cycle_phase": context.get("cycle_phase"),
            "cycle_day": context.get("cycle_day"),
            "hormone_medication_status": context.get("hormone_medication_status"),
            "method": context.get("method"),
        }

    @staticmethod
    def _medical_order_data(item: MedicalOrder) -> dict[str, Any]:
        return {
            "id": item.id,
            "ocr_result_id": item.ocr_result_id,
            "drug_name": item.drug_name,
            "standard_drug_id": item.standard_drug_id,
            "specification": item.specification,
            "dosage_value": _json_value(item.dosage_value),
            "dosage_unit": item.dosage_unit,
            "frequency": item.frequency,
            "course": item.course,
            "route": item.route,
            "instructions": item.instructions,
            "order_date": item.order_date.isoformat(),
            "explicitly_stopped": item.explicitly_stopped,
            "review_required": item.review_required,
        }

    @staticmethod
    def _abnormal_status(item: LabObservation) -> str:
        if item.reference_lower is None and item.reference_upper is None:
            return "unknown"
        if item.reference_lower is not None and item.numeric_value < item.reference_lower:
            return "low"
        if item.reference_upper is not None and item.numeric_value > item.reference_upper:
            return "high"
        return "normal"

    @staticmethod
    def _imaging_data(item: ImagingReport) -> dict[str, Any]:
        return {
            "id": item.id,
            "ocr_result_id": item.ocr_result_id,
            "examination_name": item.examination_name,
            "body_part": item.body_part,
            "examination_method": item.examination_method,
            "examination_date": _json_value(item.examined_at),
            "report_date": _json_value(item.reported_at),
            "findings": item.findings_text,
            "impression": item.conclusion_text,
        }

    @staticmethod
    def _outpatient_data(item: OutpatientRecord) -> dict[str, Any]:
        return {
            "id": item.id,
            "ocr_result_id": item.ocr_result_id,
            "facility": item.hospital_name,
            "department": item.department_name,
            "doctor_name": item.doctor_name,
            "visit_date": item.visit_date.isoformat(),
            "chief_complaint": item.chief_complaint,
            "diagnosis_summary": item.diagnosis_summary,
            "treatment_plan": item.treatment_plan,
            "medical_advice": item.medical_advice,
        }

    @staticmethod
    def _convert_lab_value(
        metric_id: str,
        value: float,
        from_unit: str | None,
        to_unit: str,
    ) -> float | None:
        conversions = {
            ("glucose", "mg/dL", "mmol/L"): 1 / 18,
            ("glucose", "mmol/L", "mg/dL"): 18,
            ("total_cholesterol", "mg/dL", "mmol/L"): 0.02586,
            ("total_cholesterol", "mmol/L", "mg/dL"): 1 / 0.02586,
            ("testosterone", "ng/dL", "nmol/L"): 0.0347,
            ("testosterone", "nmol/L", "ng/dL"): 1 / 0.0347,
        }
        factor = conversions.get((metric_id, from_unit, to_unit))
        return round(value * factor, 6) if factor is not None else None

    @staticmethod
    def _hormone_context_incomplete(metric_id: str, items: list[dict[str, Any]]) -> bool:
        hormone_metrics = {
            "lh",
            "fsh",
            "estradiol",
            "progesterone",
            "total_testosterone",
            "testosterone",
        }
        if metric_id not in hormone_metrics:
            return False
        return any(
            not item["cycle_phase"]
            or item["hormone_medication_status"] is None
            or not item["method"]
            for item in items
        )

    @staticmethod
    def _list_item(
        report: ReportSnapshot,
        *,
        has_updates: bool,
        reused: bool,
    ) -> dict[str, Any]:
        return {
            "report_id": report.id,
            "status": report.report_status,
            "generated_at": report.report_generated_at.isoformat()
            if report.report_generated_at
            else None,
            "snapshot_hash": report.snapshot_hash,
            "source_digest": report.source_digest,
            "previous_report_id": report.previous_report_id,
            "has_updates": has_updates,
            "reused": reused,
            "failure_reason": report.failure_reason,
            "missing_sections": (report.snapshot_json or {})
            .get("summary", {})
            .get("missing_sections", []),
        }

    @classmethod
    def _detail(
        cls,
        report: ReportSnapshot,
        *,
        has_updates: bool,
        reused: bool,
    ) -> dict[str, Any]:
        return {
            **cls._list_item(report, has_updates=has_updates, reused=reused),
            "snapshot": report.snapshot_json or {},
            "date_sources": report.date_source_json or {},
            "data_freshness": report.freshness_result_json or {},
        }
