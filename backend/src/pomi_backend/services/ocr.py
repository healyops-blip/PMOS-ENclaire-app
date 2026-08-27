"""Authenticated OCR task creation, lookup, and manual retry service."""

from __future__ import annotations

import hashlib
from typing import Any

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import OCRFieldResult, OCRResult, OCRTask, UserAccount
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import DocumentRepository, OCRRepository, PatientRepository
from pomi_backend.services.ocr_prompts import PROMPT_VERSION, SCHEMA_VERSION


def task_data(task: OCRTask) -> dict[str, Any]:
    return {
        "id": task.id,
        "document_id": task.document_id,
        "document_revision_id": task.document_revision_id,
        "material_type": task.material_type,
        "status": task.status,
        "model": task.model_name,
        "prompt_version": task.prompt_version,
        "schema_version": task.schema_version,
        "attempt_number": task.attempt_number,
        "parent_task_id": task.parent_task_id,
        "provider_attempts": task.provider_attempts,
        "attempt_history": task.attempt_history,
        "duration_ms": task.duration_ms,
        "error": None
        if task.error_code is None
        else {
            "category": task.error_category,
            "code": task.error_code,
            "message": task.error_message,
        },
        "result_source": task.result_source,
        "created_at": task.created_at.isoformat(),
        "updated_at": task.updated_at.isoformat(),
    }


def result_data(result: OCRResult, fields: list[OCRFieldResult]) -> dict[str, Any]:
    return {
        "id": result.id,
        "task_id": result.task_id,
        "raw_response": result.raw_response,
        "validated_draft": result.validated_draft,
        "user_modified_data": result.user_modified_data,
        "confirmed_data": result.confirmed_data,
        "fields": [
            {
                "id": field.id,
                "path": field.field_path,
                "source_text": field.source_text,
                "parsed_value": field.parsed_value,
                "confidence": field.confidence,
                "uncertainty_reason": field.uncertainty_reason,
                "source_region": field.source_region,
                "user_value": field.user_value,
                "confirmation_status": field.confirmation_status,
            }
            for field in fields
        ],
        "created_at": result.created_at.isoformat(),
    }


class OCRTaskService:
    def __init__(self, session: Session, account: UserAccount, *, model_name: str) -> None:
        self.session = session
        self.account = account
        self.model_name = model_name
        self.patient = PatientRepository(session).get_or_create(account.uid)
        self.repository = OCRRepository(session, self.patient.patient_id)
        self.documents = DocumentRepository(session, self.patient.patient_id)

    def owned(self, task_id: str) -> OCRTask:
        task = self.repository.get(task_id)
        if task is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR task was not found.", 404)
        return task

    def create(self, document_id: str, revision_id: str) -> tuple[OCRTask, bool]:
        document = self.documents.get(document_id)
        if document is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Document was not found.", 404)
        revision = self.documents.revision(document.id, revision_id)
        if revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Document revision was not found.", 404)
        if not document.processing_notice_version or not document.processing_notice_accepted_at:
            raise BusinessError(
                "EXTERNAL_PROCESSING_CONSENT_REQUIRED",
                "External OCR processing consent is required.",
                409,
            )
        key = self._key(
            self.account.uid,
            revision.file_hash,
            document.document_type,
            self.model_name,
            PROMPT_VERSION,
            SCHEMA_VERSION,
        )
        existing = self.repository.by_deduplication_key(key)
        if existing is not None:
            return existing, False
        task = OCRTask(
            id=new_uuid(),
            patient_id=self.patient.patient_id,
            requested_by_uid=self.account.uid,
            document_id=document.id,
            document_revision_id=revision.id,
            material_type=document.document_type,
            model_name=self.model_name,
            prompt_version=PROMPT_VERSION,
            schema_version=SCHEMA_VERSION,
            deduplication_key=key,
        )
        try:
            self.repository.add_task(task)
            self.session.commit()
            self.session.refresh(task)
            return task, True
        except IntegrityError:
            self.session.rollback()
            existing = self.repository.by_deduplication_key(key)
            if existing is None:
                raise
            return existing, False

    def result(self, task: OCRTask) -> dict[str, Any]:
        result = self.repository.result(task.id)
        if result is None:
            raise BusinessError("OCR_RESULT_NOT_READY", "OCR result is not ready.", 409)
        return result_data(result, self.repository.fields(result.id))

    def retry(self, task_id: str) -> tuple[OCRTask, bool]:
        original = self.owned(task_id)
        if original.status not in {"failed", "timed_out"}:
            raise BusinessError("OCR_TASK_NOT_RETRYABLE", "OCR task cannot be retried.", 409)
        document = self.documents.get(original.document_id)
        revision = self.documents.revision(original.document_id, original.document_revision_id)
        if document is None or revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR source revision was not found.", 404)
        existing = self.repository.retry_for(original.id)
        if existing is not None:
            return existing, False
        task = OCRTask(
            id=new_uuid(),
            patient_id=original.patient_id,
            requested_by_uid=self.account.uid,
            document_id=original.document_id,
            document_revision_id=original.document_revision_id,
            material_type=original.material_type,
            model_name=original.model_name,
            prompt_version=original.prompt_version,
            schema_version=original.schema_version,
            attempt_number=original.attempt_number + 1,
            parent_task_id=original.id,
            deduplication_key=self._key(original.deduplication_key, "manual-retry"),
        )
        try:
            self.repository.add_task(task)
            self.session.commit()
            self.session.refresh(task)
            return task, True
        except IntegrityError:
            self.session.rollback()
            existing = self.repository.retry_for(original.id)
            if existing is None:
                raise
            return existing, False

    @staticmethod
    def _key(*parts: str) -> str:
        return hashlib.sha256("\x1f".join(parts).encode()).hexdigest()
