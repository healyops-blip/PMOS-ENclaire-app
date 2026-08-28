"""Authenticated patient statement API."""

from fastapi import APIRouter, Request, status

from pomi_backend.api.business import BusinessError, success
from pomi_backend.api.dependencies import (
    PatientNoteRewriteServiceDependency,
    PatientNoteServiceDependency,
)
from pomi_backend.schemas.patient_notes import (
    PatientNoteCopy,
    PatientNoteCreate,
    PatientNoteUpdate,
)
from pomi_backend.services.patient_note_rewrite import PatientNoteRewriteRequest
from pomi_backend.services.patient_notes import patient_note_data

router = APIRouter(prefix="/api/patient-notes", tags=["patient-notes"])


@router.post("", status_code=status.HTTP_201_CREATED)
def create_note(
    payload: PatientNoteCreate, request: Request, service: PatientNoteServiceDependency
) -> dict:
    return success(request, patient_note_data(service.create(payload)))


@router.get("/latest")
def latest_note(request: Request, service: PatientNoteServiceDependency) -> dict:
    note = service.latest()
    return success(request, patient_note_data(note) if note else None)


@router.put("/{note_id}")
def update_note(
    note_id: str,
    payload: PatientNoteUpdate,
    request: Request,
    service: PatientNoteServiceDependency,
) -> dict:
    return success(request, patient_note_data(service.update(note_id, payload)))


@router.post("/{note_id}/confirm")
def confirm_note(note_id: str, request: Request, service: PatientNoteServiceDependency) -> dict:
    return success(request, patient_note_data(service.confirm(note_id)))


@router.post("/{note_id}/skip")
def skip_note(note_id: str, request: Request, service: PatientNoteServiceDependency) -> dict:
    return success(request, patient_note_data(service.skip(note_id)))


@router.post("/{note_id}/copy", status_code=status.HTTP_201_CREATED)
def copy_note(
    note_id: str,
    payload: PatientNoteCopy,
    request: Request,
    service: PatientNoteServiceDependency,
) -> dict:
    return success(request, patient_note_data(service.copy(note_id, payload)))


@router.post("/{note_id}/rewrite")
def rewrite_note(
    note_id: str,
    request: Request,
    service: PatientNoteServiceDependency,
    rewrite: PatientNoteRewriteServiceDependency,
) -> dict:
    note = service.owned(note_id)
    if note.status not in {"draft", "confirmed"}:
        raise BusinessError("NOTE_NOT_EDITABLE", "Patient note is not editable.", 409)
    if not (note.original_text and note.original_text.strip()):
        raise BusinessError("NOTE_EMPTY", "Patient note original_text is empty.", 422)
    rewritten = rewrite.rewrite(
        PatientNoteRewriteRequest(
            original_text=note.original_text,
            visit_context=note.visit_context,
        )
    )
    return success(request, {"rewritten_text": rewritten})
