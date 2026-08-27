"""Confirmed patient notes, immutable report snapshots, and PDF metadata."""

from __future__ import annotations

import hashlib
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    ImagingReport,
    LabObservation,
    MedicalOrder,
    Medication,
    MenstrualCycle,
    OcrResult,
    OcrTask,
    OutpatientRecord,
    PatientNote,
    ReportFile,
    ReportSnapshot,
    ReportSource,
    UserAccount,
    WeightRecord,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.schemas.reports import PatientNoteInput, ReportCreate
from pomi_backend.services.document_storage import private_path
from pomi_backend.services.health_records import HealthRecordService, medication_data, weight_data

DEFAULT_SECTIONS = [
    "profile",
    "patient_note",
    "medications",
    "labs",
    "imaging",
    "outpatient",
    "cycles",
    "weights",
]


def canonical_digest(value: Any) -> str:
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        default=lambda item: item.isoformat(),
    )
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def note_data(note: PatientNote) -> dict[str, Any]:
    return {
        "id": note.id,
        "original_text": note.original_text,
        "confirmed_text": note.confirmed_text,
        "confirmation_status": note.confirmation_status,
        "confirmed_at": note.confirmed_at.isoformat() if note.confirmed_at else None,
        "created_at": note.created_at.isoformat(),
        "updated_at": note.updated_at.isoformat(),
    }


def report_list_data(report: ReportSnapshot) -> dict[str, Any]:
    return {
        "report_id": report.id,
        "status": report.status,
        "generated_at": report.generated_at.isoformat(),
        "snapshot_hash": report.snapshot_hash,
        "failure_reason": report.failure_reason,
    }


def pdf_data(file: ReportFile, report_id: str) -> dict[str, Any]:
    return {
        "report_id": report_id,
        "file_id": file.id if file.generation_status == "succeeded" else None,
        "generation_status": file.generation_status,
        "file_name": f"pomi-report-{report_id}.pdf"
        if file.generation_status == "succeeded"
        else None,
        "mime_type": "application/pdf" if file.generation_status == "succeeded" else None,
        "file_size_bytes": file.file_size_bytes,
        "file_hash": file.file_hash,
        "generated_at": file.generated_at.isoformat() if file.generated_at else None,
        "download_url": f"/api/reports/{report_id}/pdf/file"
        if file.generation_status == "succeeded"
        else None,
        "download_expires_at": None,
        "failure_reason": file.failure_reason,
    }


class ReportService:
    def __init__(self, session: Session, account: UserAccount, storage_root: Path) -> None:
        self.session = session
        self.account = account
        self.storage_root = storage_root
        self.health = HealthRecordService(session, account)

    def latest_note(self) -> PatientNote | None:
        return self.session.scalar(
            select(PatientNote)
            .where(PatientNote.patient_id == self.health.profile().patient_id)
            .order_by(PatientNote.created_at.desc())
            .limit(1)
        )

    def save_note(self, payload: PatientNoteInput, note_id: str | None = None) -> PatientNote:
        profile = self.health.profile()
        if note_id is None:
            note = PatientNote(
                patient_id=profile.patient_id,
                original_text=payload.original_text,
                confirmation_status=payload.confirmation_status,
            )
            self.session.add(note)
        else:
            note = self.session.scalar(
                select(PatientNote).where(
                    PatientNote.id == note_id,
                    PatientNote.patient_id == profile.patient_id,
                )
            )
            if note is None:
                raise BusinessError("RESOURCE_NOT_FOUND", "Patient note was not found.", 404)
            note.original_text = payload.original_text
            note.confirmation_status = payload.confirmation_status
        note.confirmed_text = payload.confirmed_text
        if payload.confirmation_status == "confirmed":
            note.confirmed_by_uid = self.account.uid
            note.confirmed_at = utc_now()
        else:
            note.confirmed_by_uid = None
            note.confirmed_at = None
        note.updated_at = utc_now()
        self.session.commit()
        self.session.refresh(note)
        return note

    def create_report(self, payload: ReportCreate, idempotency_key: str) -> ReportSnapshot:
        existing = self.session.scalar(
            select(ReportSnapshot).where(
                ReportSnapshot.generated_by_uid == self.account.uid,
                ReportSnapshot.idempotency_key == idempotency_key,
            )
        )
        if existing is not None:
            return existing
        profile = self.health.profile()
        note = None
        if payload.patient_note_id:
            note = self.session.scalar(
                select(PatientNote).where(
                    PatientNote.id == payload.patient_note_id,
                    PatientNote.patient_id == profile.patient_id,
                )
            )
            if note is None:
                raise BusinessError("RESOURCE_NOT_FOUND", "Patient note was not found.", 404)
        else:
            note = self.session.scalar(
                select(PatientNote)
                .where(
                    PatientNote.patient_id == profile.patient_id,
                    PatientNote.confirmation_status == "confirmed",
                )
                .order_by(PatientNote.created_at.desc())
                .limit(1)
            )
        if note is not None and note.confirmation_status != "confirmed":
            raise BusinessError("REPORT_SOURCE_INCOMPLETE", "Patient note must be confirmed.", 409)
        sections = list(dict.fromkeys(payload.include_sections or DEFAULT_SECTIONS))
        snapshot, sources = self._build_snapshot(note, sections)
        digest = canonical_digest(snapshot)
        previous = self.session.scalar(
            select(ReportSnapshot)
            .where(ReportSnapshot.patient_id == profile.patient_id)
            .order_by(ReportSnapshot.generated_at.desc())
            .limit(1)
        )
        report = ReportSnapshot(
            patient_id=profile.patient_id,
            patient_note_id=note.id if note else None,
            previous_report_id=previous.id if previous else None,
            status="succeeded",
            snapshot=snapshot,
            data_freshness={"generated_at": utc_now().isoformat()},
            source_digest=canonical_digest(sources),
            snapshot_hash=digest,
            include_sections=sections,
            idempotency_key=idempotency_key,
            generated_by_uid=self.account.uid,
        )
        self.session.add(report)
        self.session.flush()
        for number, source in enumerate(sources, start=1):
            self.session.add(ReportSource(report_id=report.id, source_number=number, **source))
        self.session.commit()
        self.session.refresh(report)
        return report

    def _build_snapshot(
        self, note: PatientNote | None, sections: list[str]
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        profile = self.health.profile()
        medications = (
            list(
                self.session.scalars(
                    select(Medication)
                    .where(Medication.patient_id == profile.patient_id)
                    .order_by(Medication.created_at)
                )
            )
            if "medications" in sections
            else []
        )
        weights = (
            list(
                self.session.scalars(
                    select(WeightRecord)
                    .where(WeightRecord.patient_id == profile.patient_id)
                    .order_by(WeightRecord.measured_at)
                )
            )
            if "weights" in sections
            else []
        )
        cycles = (
            list(
                self.session.scalars(
                    select(MenstrualCycle)
                    .where(MenstrualCycle.patient_id == profile.patient_id)
                    .order_by(MenstrualCycle.start_date)
                )
            )
            if "cycles" in sections
            else []
        )
        labs = (
            list(
                self.session.scalars(
                    select(LabObservation).where(LabObservation.patient_id == profile.patient_id)
                )
            )
            if "labs" in sections
            else []
        )
        imaging = (
            list(
                self.session.scalars(
                    select(ImagingReport).where(ImagingReport.patient_id == profile.patient_id)
                )
            )
            if "imaging" in sections
            else []
        )
        orders = (
            list(
                self.session.scalars(
                    select(MedicalOrder).where(MedicalOrder.patient_id == profile.patient_id)
                )
            )
            if "medications" in sections
            else []
        )
        outpatient = (
            list(
                self.session.scalars(
                    select(OutpatientRecord).where(
                        OutpatientRecord.patient_id == profile.patient_id
                    )
                )
            )
            if "outpatient" in sections
            else []
        )
        sources: list[dict[str, Any]] = []
        trends_by_metric: dict[tuple[str, str | None], list[dict[str, Any]]] = defaultdict(list)
        for lab in labs:
            material_date = lab.sample_date or lab.report_date
            if material_date is not None:
                trends_by_metric[(lab.item_name, lab.normalized_unit or lab.raw_unit)].append(
                    {
                        "source_id": lab.id,
                        "value": lab.numeric_value,
                        "raw_value": lab.raw_value,
                        "unit": lab.normalized_unit or lab.raw_unit,
                        "date": material_date.isoformat(),
                        "date_source": "sample_date" if lab.sample_date else "report_date",
                        "abnormal_status": lab.abnormal_status or "unknown",
                        "exclusion_reason": None,
                    }
                )
            revision_id = self._revision_for_result(lab.ocr_result_id)
            sources.append(
                {
                    "source_type": "lab_observation",
                    "source_id": lab.id,
                    "document_id": lab.document_id,
                    "document_revision_id": revision_id,
                    "original_value": lab.raw_value,
                    "original_unit": lab.raw_unit,
                    "reference_range_text": lab.reference_range_text,
                    "material_date": material_date,
                    "date_source": "sample_date" if lab.sample_date else "report_date",
                }
            )
        for record, source_type, material_date in [
            *[(item, "imaging_report", item.examined_at or item.reported_at) for item in imaging],
            *[(item, "outpatient_record", item.visit_date) for item in outpatient],
        ]:
            sources.append(
                {
                    "source_type": source_type,
                    "source_id": record.id,
                    "document_id": record.document_id,
                    "document_revision_id": self._revision_for_result(record.ocr_result_id),
                    "original_value": None,
                    "original_unit": None,
                    "reference_range_text": None,
                    "material_date": material_date,
                    "date_source": "encounter_date",
                }
            )
        for order in orders:
            sources.append(
                {
                    "source_type": "medical_order",
                    "source_id": order.id,
                    "document_id": order.document_id,
                    "document_revision_id": self._revision_for_result(order.ocr_result_id),
                    "original_value": order.source_text,
                    "original_unit": None,
                    "reference_range_text": None,
                    "material_date": order.prescribed_at,
                    "date_source": "encounter_date",
                }
            )
        if note is not None and "patient_note" in sections:
            sources.append(
                {
                    "source_type": "patient_note",
                    "source_id": note.id,
                    "document_id": None,
                    "document_revision_id": None,
                    "original_value": note.confirmed_text,
                    "original_unit": None,
                    "reference_range_text": None,
                    "material_date": note.confirmed_at.date() if note.confirmed_at else None,
                    "date_source": "confirmed_at",
                }
            )
        summary = {
            "profile": {
                "patient_id": profile.patient_id,
                "nickname": profile.nickname,
                "birth_date": profile.birth_date.isoformat() if profile.birth_date else None,
                "primary_condition": profile.primary_condition,
            }
            if "profile" in sections
            else {},
            "patient_note_text": note.confirmed_text
            if note and "patient_note" in sections
            else None,
            "current_medications": [
                medication_data(item) for item in medications if item.current_status == "active"
            ],
            "latest_observations": [
                {
                    "item_name": item.item_name,
                    "raw_value": item.raw_value,
                    "unit": item.raw_unit,
                    "date": (item.sample_date or item.report_date).isoformat()
                    if item.sample_date or item.report_date
                    else None,
                }
                for item in labs
            ],
            "cycle_summary": {
                "latest_start_date": cycles[-1].start_date.isoformat() if cycles else None
            },
            "weight_summary": weight_data(weights[-1]) if weights else None,
            "disclaimers": [
                "This report organizes user-confirmed records for visit preparation.",
                "It is not a diagnosis or treatment recommendation.",
            ],
        }
        trends = [
            {
                "metric_id": canonical_digest({"name": name, "unit": unit})[:16],
                "metric_name": name,
                "unit": unit,
                "comparability": "comparable",
                "comparability_reason": None,
                "points": sorted(points, key=lambda point: point["date"] or ""),
            }
            for (name, unit), points in trends_by_metric.items()
        ]
        public_sources = [
            {
                "source_number": index,
                **{
                    key: value.isoformat() if hasattr(value, "isoformat") else value
                    for key, value in source.items()
                },
                "rule_execution_id": None,
                "file_url": f"/api/documents/{source['document_id']}/revisions/"
                f"{source['document_revision_id']}/file"
                if source["document_id"] and source["document_revision_id"]
                else None,
            }
            for index, source in enumerate(sources, start=1)
        ]
        snapshot = {
            "summary": summary,
            "trends": trends,
            "sources": public_sources,
            "data_freshness": {"source_count": len(sources)},
            "include_sections": sections,
        }
        return snapshot, sources

    def _revision_for_result(self, result_id: str) -> str | None:
        task_id = self.session.scalar(
            select(OcrResult.ocr_task_id).where(OcrResult.id == result_id)
        )
        if task_id is None:
            return None
        return self.session.scalar(
            select(OcrTask.document_revision_id).where(OcrTask.id == task_id)
        )

    def reports(self, limit: int = 20, cursor: str | None = None) -> list[ReportSnapshot]:
        statement = select(ReportSnapshot).where(
            ReportSnapshot.patient_id == self.health.profile().patient_id
        )
        if cursor is not None:
            try:
                cursor_time = datetime.fromisoformat(cursor)
            except ValueError as exc:
                raise BusinessError("VALIDATION_ERROR", "Invalid cursor.", 422) from exc
            statement = statement.where(ReportSnapshot.generated_at < cursor_time)
        return list(
            self.session.scalars(
                statement.order_by(ReportSnapshot.generated_at.desc()).limit(limit + 1)
            )
        )

    def owned_report(self, report_id: str) -> ReportSnapshot:
        report = self.session.scalar(
            select(ReportSnapshot).where(
                ReportSnapshot.id == report_id,
                ReportSnapshot.patient_id == self.health.profile().patient_id,
            )
        )
        if report is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Report was not found.", 404)
        return report

    def report_detail(self, report_id: str) -> dict[str, Any]:
        report = self.owned_report(report_id)
        return {**report_list_data(report), **report.snapshot}

    def request_pdf(self, report_id: str) -> ReportFile:
        report = self.owned_report(report_id)
        file = self.session.scalar(
            select(ReportFile).where(
                ReportFile.report_id == report.id,
                ReportFile.file_type == "pdf",
            )
        )
        if file is None:
            file = ReportFile(report_id=report.id)
            self.session.add(file)
            self.session.commit()
            self.session.refresh(file)
        return file

    def pdf(self, report_id: str) -> ReportFile:
        self.owned_report(report_id)
        file = self.session.scalar(
            select(ReportFile).where(
                ReportFile.report_id == report_id,
                ReportFile.file_type == "pdf",
            )
        )
        if file is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "PDF request was not found.", 404)
        return file

    def pdf_path(self, report_id: str) -> Path:
        file = self.pdf(report_id)
        if file.generation_status != "succeeded" or file.storage_path is None:
            raise BusinessError("PDF_GENERATION_FAILED", "PDF is not ready.", 409)
        return private_path(self.storage_root, file.storage_path)
