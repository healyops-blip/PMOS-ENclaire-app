from __future__ import annotations

from datetime import timedelta
from pathlib import Path

import pytest
from sqlalchemy.orm import Session

from pomi_backend.db.models import (
    Document,
    DocumentRevision,
    PatientNote,
    ReportSnapshot,
    ReportSource,
    UserAccount,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.repositories import (
    PatientNoteRepository,
    PatientRepository,
    ReportSnapshotRepository,
    ReportSourceRepository,
)
from pomi_backend.services.documents import purge_deleted_documents


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
    reports.update_pending(report, report_status="succeeded", report_generated_at=utc_now())
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


def test_repository_identity_fields_and_generators_cannot_cross_patient_scope(
    db_session: Session,
) -> None:
    first = _account(db_session, "3")
    second = _account(db_session, "4")
    first_patient = PatientRepository(db_session).get_or_create(first.uid)
    second_patient = PatientRepository(db_session).get_or_create(second.uid)
    notes = PatientNoteRepository(db_session, first_patient.patient_id)
    note = notes.add(PatientNote(patient_id=first_patient.patient_id, original_text="safe"))

    with pytest.raises(ValueError, match="fields are immutable"):
        notes.update(note, patient_id=second_patient.patient_id)

    reports = ReportSnapshotRepository(db_session, first_patient.patient_id)
    with pytest.raises(ValueError, match="generator is outside"):
        reports.add(
            ReportSnapshot(
                patient_id=first_patient.patient_id,
                source_digest="c" * 64,
                generated_by_uid=second.uid,
            )
        )
    report = reports.add(
        ReportSnapshot(
            patient_id=first_patient.patient_id,
            source_digest="d" * 64,
            generated_by_uid=first.uid,
        )
    )
    with pytest.raises(ValueError, match="fields are immutable"):
        reports.update_pending(report, patient_id=second_patient.patient_id)
    with pytest.raises(ValueError, match="require content"):
        reports.update_pending(report, report_status="succeeded")


def test_document_provenance_is_patient_scoped_and_prevents_file_purge(
    db_session: Session, tmp_path: Path
) -> None:
    first = _account(db_session, "5")
    second = _account(db_session, "6")
    first_patient = PatientRepository(db_session).get_or_create(first.uid)
    second_patient = PatientRepository(db_session).get_or_create(second.uid)

    def add_document(patient_id: str, uid: str, suffix: str) -> tuple[Document, DocumentRevision]:
        revision_id = f"revision-{suffix}"
        document = Document(
            id=f"document-{suffix}",
            patient_id=patient_id,
            document_type="lab_report",
            original_file_name=f"{suffix}.png",
            mime_type="image/png",
            file_size_bytes=4,
            pixel_count=1,
            page_count=1,
            file_hash=suffix * 64,
            current_revision_id=revision_id,
            uploaded_by_uid=uid,
            idempotency_key=f"upload-{suffix}",
        )
        revision = DocumentRevision(
            id=revision_id,
            document_id=document.id,
            revision_number=1,
            storage_path=f"documents/{suffix}.png",
            file_hash=suffix * 64,
            file_size_bytes=4,
            mime_type="image/png",
            pixel_count=1,
            page_count=1,
            created_by_uid=uid,
        )
        db_session.add_all([document, revision])
        db_session.flush()
        return document, revision

    first_document, first_revision = add_document(first_patient.patient_id, first.uid, "a")
    second_document, second_revision = add_document(second_patient.patient_id, second.uid, "b")
    reports = ReportSnapshotRepository(db_session, first_patient.patient_id)
    report = reports.add(
        ReportSnapshot(
            patient_id=first_patient.patient_id,
            source_digest="e" * 64,
            generated_by_uid=first.uid,
        )
    )
    sources = ReportSourceRepository(db_session, reports)
    with pytest.raises(ValueError, match="outside report scope"):
        sources.add(
            ReportSource(
                report_id=report.id,
                source_type="lab_observation",
                source_record_id="foreign-lab",
                origin_kind="medical_document",
                document_id=second_document.id,
                document_revision_id=second_revision.id,
            )
        )
    with pytest.raises(ValueError, match="cannot impersonate"):
        sources.add(
            ReportSource(
                report_id=report.id,
                source_type="patient_profile",
                source_record_id=first_patient.patient_id,
                origin_kind="patient_manual",
                document_revision_id=first_revision.id,
            )
        )
    sources.add(
        ReportSource(
            report_id=report.id,
            source_type="lab_observation",
            source_record_id="owned-lab",
            origin_kind="medical_document",
            document_id=first_document.id,
            document_revision_id=first_revision.id,
        )
    )
    storage_root = tmp_path / "storage"
    stored_file = storage_root / first_revision.storage_path
    stored_file.parent.mkdir(parents=True)
    stored_file.write_bytes(b"test")
    first_document.deleted_at = utc_now()
    first_document.purge_after = utc_now() - timedelta(seconds=1)
    db_session.commit()

    assert purge_deleted_documents(db_session, storage_root, now=utc_now()) == 0
    assert stored_file.is_file()
