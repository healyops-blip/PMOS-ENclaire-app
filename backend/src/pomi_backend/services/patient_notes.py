"""Patient statement lifecycle without rewriting or model processing."""

from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import PatientNote, UserAccount
from pomi_backend.db.models.auth import utc_now
from pomi_backend.repositories import PatientNoteRepository, PatientRepository
from pomi_backend.schemas.patient_notes import PatientNoteCopy, PatientNoteCreate, PatientNoteUpdate


def patient_note_data(note: PatientNote) -> dict[str, Any]:
    return {
        "id": note.id,
        "patient_id": note.patient_id,
        "visit_context": note.visit_context,
        "original_text": note.original_text,
        "confirmed_text": note.confirmed_text,
        "status": note.status,
        "confirmed_at": note.confirmed_at.isoformat() if note.confirmed_at else None,
        "source_note_id": note.source_note_id,
        "consumed_at": note.consumed_at.isoformat() if note.consumed_at else None,
        "created_at": note.created_at.isoformat(),
        "updated_at": note.updated_at.isoformat(),
    }


class PatientNoteService:
    def __init__(self, session: Session, account: UserAccount) -> None:
        self.session = session
        self.account = account
        patient = PatientRepository(session).get_or_create(account.uid)
        self.repository = PatientNoteRepository(session, patient.patient_id)
        self.patient_id = patient.patient_id

    def owned(self, note_id: str) -> PatientNote:
        note = self.repository.get(note_id)
        if note is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Patient note was not found.", 404)
        return note

    def latest(self) -> PatientNote | None:
        return self.repository.latest()

    def create(self, payload: PatientNoteCreate) -> PatientNote:
        note = PatientNote(
            patient_id=self.patient_id,
            original_text=payload.original_text,
            visit_context=payload.visit_context,
        )
        self.repository.add(note)
        self.session.commit()
        self.session.refresh(note)
        return note

    def update(self, note_id: str, payload: PatientNoteUpdate) -> PatientNote:
        note = self.owned(note_id)
        if note.status == "consumed":
            raise BusinessError(
                "PATIENT_NOTE_IMMUTABLE", "Consumed patient notes must be copied.", 409
            )
        self.repository.update(
            note,
            original_text=payload.original_text,
            visit_context=payload.visit_context,
            confirmed_text=None,
            confirmed_by_uid=None,
            confirmed_at=None,
            status="draft",
            updated_at=utc_now(),
        )
        self.session.commit()
        self.session.refresh(note)
        return note

    def confirm(self, note_id: str) -> PatientNote:
        note = self.owned(note_id)
        if note.status == "confirmed":
            return note
        if note.status == "consumed":
            raise BusinessError(
                "PATIENT_NOTE_IMMUTABLE", "Consumed patient notes cannot be reconfirmed.", 409
            )
        if not note.original_text.strip():
            raise BusinessError(
                "PATIENT_NOTE_EMPTY", "Use skip when there is no patient statement.", 409
            )
        now = utc_now()
        self.repository.update(
            note,
            confirmed_text=note.original_text,
            confirmed_by_uid=self.account.uid,
            confirmed_at=now,
            status="confirmed",
            updated_at=now,
        )
        self.session.commit()
        self.session.refresh(note)
        return note

    def skip(self, note_id: str) -> PatientNote:
        note = self.owned(note_id)
        if note.status == "skipped":
            return note
        if note.status == "consumed":
            raise BusinessError(
                "PATIENT_NOTE_IMMUTABLE", "Consumed patient notes cannot be skipped.", 409
            )
        now = utc_now()
        self.repository.update(
            note,
            confirmed_text=None,
            confirmed_by_uid=self.account.uid,
            confirmed_at=now,
            status="skipped",
            updated_at=now,
        )
        self.session.commit()
        self.session.refresh(note)
        return note

    def copy(self, note_id: str, payload: PatientNoteCopy) -> PatientNote:
        source = self.owned(note_id)
        if source.status not in {"confirmed", "consumed"}:
            raise BusinessError(
                "PATIENT_NOTE_NOT_CONFIRMED", "Only confirmed history can be copied.", 409
            )
        note = PatientNote(
            patient_id=self.patient_id,
            original_text=source.confirmed_text or source.original_text,
            visit_context=payload.visit_context,
            source_note_id=source.id,
            status="draft",
        )
        self.repository.add(note)
        self.session.commit()
        self.session.refresh(note)
        return note
