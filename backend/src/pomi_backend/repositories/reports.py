"""Patient-scoped repositories for statements and immutable report provenance."""

from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.db.models import PatientNote, ReportSnapshot, ReportSource


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
            .order_by(PatientNote.created_at.desc())
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
        for field, value in changes.items():
            setattr(note, field, value)
        self.session.flush()
        return note


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

    def list_succeeded(self) -> list[ReportSnapshot]:
        return list(
            self.session.scalars(
                select(ReportSnapshot)
                .where(
                    ReportSnapshot.patient_id == self.patient_id,
                    ReportSnapshot.report_status == "succeeded",
                )
                .order_by(
                    ReportSnapshot.report_generated_at.desc(),
                    ReportSnapshot.created_at.desc(),
                )
            )
        )

    def latest_succeeded(self) -> ReportSnapshot | None:
        return self.session.scalar(
            select(ReportSnapshot)
            .where(
                ReportSnapshot.patient_id == self.patient_id,
                ReportSnapshot.report_status == "succeeded",
            )
            .order_by(
                ReportSnapshot.report_generated_at.desc(),
                ReportSnapshot.created_at.desc(),
            )
            .limit(1)
        )

    def add(self, report: ReportSnapshot) -> ReportSnapshot:
        if report.patient_id != self.patient_id:
            raise ValueError("report snapshot is outside repository scope")
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
        if source.origin_kind == "patient_manual" and source.document_id is not None:
            raise ValueError("patient manual sources cannot impersonate medical documents")
        self.session.add(source)
        self.session.flush()
        return source

    def list_for_report(self, report_id: str) -> list[ReportSource]:
        if self.reports.get(report_id) is None:
            return []
        return list(
            self.session.scalars(
                select(ReportSource)
                .where(ReportSource.report_id == report_id)
                .order_by(ReportSource.included_at, ReportSource.id)
            )
        )
