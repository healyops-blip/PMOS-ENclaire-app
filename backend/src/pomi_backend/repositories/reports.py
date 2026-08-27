"""Patient-scoped repositories for statements and immutable report provenance."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy import update as sql_update
from sqlalchemy.orm import Session

from pomi_backend.db.models import (
    Document,
    DocumentRevision,
    PatientNote,
    PatientProfile,
    ReportSnapshot,
    ReportSource,
)

_PATIENT_NOTE_MUTABLE_FIELDS = {
    "original_text",
    "visit_context",
    "confirmed_text",
    "confirmed_by_uid",
    "confirmed_at",
    "status",
    "consumed_at",
    "updated_at",
}
_REPORT_MUTABLE_FIELDS = {
    "report_status",
    "snapshot_json",
    "date_source_json",
    "freshness_result_json",
    "snapshot_hash",
    "report_generated_at",
    "failure_reason",
}


class PatientNoteRepository:
    def __init__(self, session: Session, patient_id: str) -> None:
        self.session = session
        self.patient_id = patient_id

    def get(self, note_id: str) -> PatientNote | None:
        return self.session.scalar(
            select(PatientNote).where(
                PatientNote.id == note_id,
                PatientNote.patient_id == self.patient_id,
            )
        )

    def latest(self) -> PatientNote | None:
        return self.session.scalar(
            select(PatientNote)
            .where(PatientNote.patient_id == self.patient_id)
            .order_by(PatientNote.created_at.desc(), PatientNote.id.desc())
            .limit(1)
        )

    def add(self, note: PatientNote) -> PatientNote:
        if note.patient_id != self.patient_id:
            raise ValueError("patient note is outside repository scope")
        self.session.add(note)
        self.session.flush()
        return note

    def update(self, note: PatientNote, **changes: Any) -> PatientNote:
        if self.get(note.id) is None:
            raise ValueError("patient note is outside repository scope")
        if note.status == "consumed":
            raise ValueError("consumed patient notes are immutable")
        unexpected = changes.keys() - _PATIENT_NOTE_MUTABLE_FIELDS
        if unexpected:
            raise ValueError(f"patient note fields are immutable: {sorted(unexpected)}")
        target_status = changes.get("status", note.status)
        if target_status not in {"draft", "consumed"}:
            raise ValueError("confirmation and skip decisions require the atomic decision method")
        if target_status == "consumed" and (
            note.status != "confirmed" or changes.get("consumed_at") is None
        ):
            raise ValueError("only confirmed notes can be consumed with a timestamp")
        if changes.get("confirmed_by_uid") is not None:
            owner_uid = self.session.scalar(
                select(PatientProfile.account_uid).where(
                    PatientProfile.patient_id == self.patient_id
                )
            )
            if changes["confirmed_by_uid"] != owner_uid:
                raise ValueError("patient note confirmer is outside repository scope")
        for field, value in changes.items():
            setattr(note, field, value)
        self.session.flush()
        return note

    def decide(
        self,
        note: PatientNote,
        *,
        target_status: str,
        account_uid: str,
        decided_at: datetime,
    ) -> PatientNote:
        if target_status not in {"confirmed", "skipped"}:
            raise ValueError("unsupported patient note decision")
        owner_uid = self.session.scalar(
            select(PatientProfile.account_uid).where(PatientProfile.patient_id == self.patient_id)
        )
        if account_uid != owner_uid:
            raise ValueError("patient note confirmer is outside repository scope")
        values: dict[str, Any] = {
            "confirmed_by_uid": account_uid,
            "confirmed_at": decided_at,
            "status": target_status,
            "updated_at": decided_at,
        }
        values["confirmed_text"] = (
            PatientNote.original_text if target_status == "confirmed" else None
        )
        self.session.execute(
            sql_update(PatientNote)
            .where(
                PatientNote.id == note.id,
                PatientNote.patient_id == self.patient_id,
                PatientNote.status.not_in(("consumed", target_status)),
            )
            .values(**values)
            .execution_options(synchronize_session=False)
        )
        self.session.expire_all()
        refreshed = self.get(note.id)
        if refreshed is None:
            raise ValueError("patient note is outside repository scope")
        return refreshed


class ReportSnapshotRepository:
    def __init__(self, session: Session, patient_id: str) -> None:
        self.session = session
        self.patient_id = patient_id

    def get(self, report_id: str) -> ReportSnapshot | None:
        return self.session.scalar(
            select(ReportSnapshot).where(
                ReportSnapshot.id == report_id,
                ReportSnapshot.patient_id == self.patient_id,
            )
        )

    def find_by_source_digest(self, source_digest: str) -> ReportSnapshot | None:
        return self.session.scalar(
            select(ReportSnapshot).where(
                ReportSnapshot.patient_id == self.patient_id,
                ReportSnapshot.source_digest == source_digest,
            )
        )

    def add(self, report: ReportSnapshot) -> ReportSnapshot:
        if report.patient_id != self.patient_id:
            raise ValueError("report snapshot is outside repository scope")
        owner_uid = self.session.scalar(
            select(PatientProfile.account_uid).where(PatientProfile.patient_id == self.patient_id)
        )
        if report.generated_by_uid != owner_uid:
            raise ValueError("report generator is outside repository scope")
        if report.patient_note_id is not None:
            note = self.session.scalar(
                select(PatientNote).where(
                    PatientNote.id == report.patient_note_id,
                    PatientNote.patient_id == self.patient_id,
                )
            )
            if note is None:
                raise ValueError("patient note is outside report scope")
        if report.previous_report_id is not None:
            previous = self.get(report.previous_report_id)
            if previous is None or previous.report_status != "succeeded":
                raise ValueError("previous report must be a successful snapshot for this patient")
        self.session.add(report)
        self.session.flush()
        return report

    def update_pending(self, report: ReportSnapshot, **changes: Any) -> ReportSnapshot:
        if self.get(report.id) is None:
            raise ValueError("report snapshot is outside repository scope")
        if report.report_status == "succeeded":
            raise ValueError("successful report snapshots are immutable")
        unexpected = changes.keys() - _REPORT_MUTABLE_FIELDS
        if unexpected:
            raise ValueError(f"report snapshot fields are immutable: {sorted(unexpected)}")
        target_status = changes.get("report_status", report.report_status)
        if target_status == "succeeded" and any(
            changes.get(field, getattr(report, field)) is None
            for field in ("snapshot_json", "snapshot_hash", "report_generated_at")
        ):
            raise ValueError("successful report snapshots require content, hash and timestamp")
        for field, value in changes.items():
            setattr(report, field, value)
        self.session.flush()
        return report


class ReportSourceRepository:
    def __init__(self, session: Session, report_repository: ReportSnapshotRepository) -> None:
        self.session = session
        self.reports = report_repository

    def add(self, source: ReportSource) -> ReportSource:
        report = self.reports.get(source.report_id)
        if report is None:
            raise ValueError("report source is outside repository scope")
        if report.report_status == "succeeded":
            raise ValueError("successful report provenance is immutable")
        if source.origin_kind == "medical_document" and (
            source.document_id is None or source.document_revision_id is None
        ):
            raise ValueError("medical document sources require an explicit revision")
        if source.origin_kind == "medical_document":
            document = self.session.scalar(
                select(Document).where(
                    Document.id == source.document_id,
                    Document.patient_id == self.reports.patient_id,
                )
            )
            revision = self.session.scalar(
                select(DocumentRevision).where(
                    DocumentRevision.id == source.document_revision_id,
                    DocumentRevision.document_id == source.document_id,
                )
            )
            if document is None or revision is None:
                raise ValueError("medical document revision is outside report scope")
        elif source.document_id is not None or source.document_revision_id is not None:
            raise ValueError("non-document sources cannot impersonate medical documents")
        if source.origin_kind == "rule_execution":
            if source.rule_execution_id is None:
                raise ValueError("rule execution sources require an execution id")
        elif source.rule_execution_id is not None:
            raise ValueError("non-rule sources cannot impersonate rule executions")
        if source.source_type == "patient_note":
            note = self.session.scalar(
                select(PatientNote).where(
                    PatientNote.id == source.source_record_id,
                    PatientNote.patient_id == self.reports.patient_id,
                )
            )
            if note is None:
                raise ValueError("patient note source is outside report scope")
        self.session.add(source)
        self.session.flush()
        return source
