from __future__ import annotations

import pytest
from sqlalchemy.orm import Session

from pomi_backend.db.models import PatientNote, ReportSnapshot, ReportSource, UserAccount
from pomi_backend.repositories import (
    PatientNoteRepository,
    PatientRepository,
    ReportSnapshotRepository,
    ReportSourceRepository,
)


def _account(session: Session, name: str) -> UserAccount:
    account = UserAccount(
        uid=f"00000000-0000-0000-0000-{name:0>12}",
        account_name=f"report-{name}",
        password_hash="test-only",
    )
    session.add(account)
    session.flush()
    return account


def test_successful_snapshots_are_immutable_and_sources_are_explicit(db_session: Session) -> None:
    account = _account(db_session, "1")
    patient = PatientRepository(db_session).get_or_create(account.uid)
    notes = PatientNoteRepository(db_session, patient.patient_id)
    note = notes.add(
        PatientNote(patient_id=patient.patient_id, original_text="verbatim", status="confirmed")
    )
    reports = ReportSnapshotRepository(db_session, patient.patient_id)
    report = reports.add(
        ReportSnapshot(
            patient_id=patient.patient_id,
            patient_note_id=note.id,
            source_digest="a" * 64,
            snapshot_hash="b" * 64,
            snapshot_json={"frozen": True},
            generated_by_uid=account.uid,
            report_status="pending",
        )
    )
    sources = ReportSourceRepository(db_session, reports)
    manual = sources.add(
        ReportSource(
            report_id=report.id,
            source_type="patient_note",
            source_record_id=note.id,
            origin_kind="patient_manual",
        )
    )
    assert manual.document_id is None
    with pytest.raises(ValueError, match="explicit revision"):
        sources.add(
            ReportSource(
                report_id=report.id,
                source_type="lab_observation",
                source_record_id="lab-1",
                origin_kind="medical_document",
                document_id="document-1",
            )
        )
    reports.update_pending(report, report_status="succeeded")
    assert reports.find_by_source_digest("a" * 64) is report
    with pytest.raises(ValueError, match="immutable"):
        reports.update_pending(report, snapshot_json={"frozen": False})
    with pytest.raises(ValueError, match="provenance is immutable"):
        sources.add(
            ReportSource(
                report_id=report.id,
                source_type="patient_profile",
                source_record_id=patient.patient_id,
                origin_kind="system_record",
            )
        )


def test_consumed_patient_note_cannot_be_updated(db_session: Session) -> None:
    account = _account(db_session, "2")
    patient = PatientRepository(db_session).get_or_create(account.uid)
    repository = PatientNoteRepository(db_session, patient.patient_id)
    note = repository.add(
        PatientNote(patient_id=patient.patient_id, original_text="locked", status="consumed")
    )
    with pytest.raises(ValueError, match="immutable"):
        repository.update(note, original_text="changed")
