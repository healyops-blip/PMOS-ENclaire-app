"""Authenticated OCR task creation, lookup, and manual retry service."""

from __future__ import annotations

import hashlib
import json
from typing import Any

from jsonschema import validate
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    LabObservation,
    OCRFallbackUse,
    OCRFieldResult,
    OCRResult,
    OCRTask,
    UserAccount,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import (
    DocumentRepository,
    LabObservationRepository,
    OCRRepository,
    PatientRepository,
)
from pomi_backend.services.lab_rules import FieldIssue, normalize_lab_item, p0_evaluation
from pomi_backend.services.ocr_fallback import (
    ALLOWED_FAILURE_CATEGORIES,
    FALLBACK_DATA_VERSION,
    fallback_match,
    mark_fallback_confirmed,
)
from pomi_backend.services.ocr_prompts import PROMPT_VERSION, SCHEMA_VERSION, schema_for


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


def result_data(
    result: OCRResult,
    fields: list[OCRFieldResult],
    *,
    source_document: dict[str, Any] | None = None,
) -> dict[str, Any]:
    data = {
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
    if source_document is not None:
        data["source_document"] = source_document
    return data


def lab_observation_data(observation: LabObservation) -> dict[str, Any]:
    def decimal(value: Any) -> str | None:
        return None if value is None else format(value, "f")

    return {
        "id": observation.id,
        "patient_id": observation.patient_id,
        "visit_id": observation.visit_id,
        "document_id": observation.document_id,
        "document_revision_id": observation.document_revision_id,
        "ocr_result_id": observation.ocr_result_id,
        "item_index": observation.item_index,
        "original_item_name": observation.original_item_name,
        "standard_metric_id": observation.standard_metric_id,
        "mapping_status": observation.mapping_status,
        "raw_value": observation.raw_value,
        "numeric_value": decimal(observation.numeric_value),
        "original_unit": observation.original_unit,
        "standard_unit": observation.standard_unit,
        "reference_range_raw": observation.reference_range_raw,
        "reference_lower": decimal(observation.reference_lower),
        "reference_upper": decimal(observation.reference_upper),
        "abnormal_status": observation.abnormal_status,
        "sample_date": None
        if observation.sample_date is None
        else observation.sample_date.isoformat(),
        "exam_date": None if observation.exam_date is None else observation.exam_date.isoformat(),
        "report_date": None
        if observation.report_date is None
        else observation.report_date.isoformat(),
        "visit_date": None
        if observation.visit_date is None
        else observation.visit_date.isoformat(),
        "trend_date": None
        if observation.trend_date is None
        else observation.trend_date.isoformat(),
        "trend_date_source": observation.trend_date_source,
        "confirmed_by_uid": observation.confirmed_by_uid,
        "confirmed_at": observation.confirmed_at.isoformat(),
    }


class OCRTaskService:
    def __init__(self, session: Session, account: UserAccount, *, model_name: str) -> None:
        self.session = session
        self.account = account
        self.model_name = model_name
        self.patient = PatientRepository(session).get_or_create(account.uid)
        self.repository = OCRRepository(session, self.patient.patient_id)
        self.documents = DocumentRepository(session, self.patient.patient_id)
        self.labs = LabObservationRepository(session, self.patient.patient_id)

    def owned(self, task_id: str) -> OCRTask:
        task = self.repository.get(task_id)
        if task is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR task was not found.", 404)
        return task

    def data(self, task: OCRTask) -> dict[str, Any]:
        fallback = self.repository.fallback_use(task.id)
        return {
            **task_data(task),
            "fallback": None if fallback is None else self._fallback_data(fallback),
        }

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
        document = self.documents.get(task.document_id, include_deleted=True)
        revision = self.documents.revision(task.document_id, task.document_revision_id)
        source = None
        if document is not None and revision is not None:
            source = {
                "document_id": document.id,
                "document_revision_id": revision.id,
                "original_file_name": document.original_file_name,
                "mime_type": revision.mime_type,
                "revision_number": revision.revision_number,
                "file_endpoint": (f"/documents/{document.id}/revisions/{revision.id}/file"),
            }
        data = result_data(
            result,
            self.repository.fields(result.id),
            source_document=source,
        )
        data["source"] = {
            "document_id": task.document_id,
            "document_revision_id": task.document_revision_id,
            "file_url": (
                f"/api/documents/{task.document_id}/revisions/{task.document_revision_id}/file"
            ),
        }
        data["result_source"] = task.result_source
        fallback = self.repository.fallback_use(task.id)
        data["fallback"] = None if fallback is None else self._fallback_data(fallback)
        return data

    def fallback_eligibility(self, task_id: str) -> dict[str, Any]:
        task = self.owned(task_id)
        eligible, reason = self._fallback_match(task)
        return {
            "eligible": eligible is not None,
            "data_version": FALLBACK_DATA_VERSION if eligible is not None else None,
            "reason": reason,
        }

    def use_fallback(self, task_id: str, *, accept: bool, data_version: str) -> dict[str, Any]:
        task = self.owned(task_id)
        if not accept:
            return {**self.data(task), "fallback_declined": True}
        if data_version != FALLBACK_DATA_VERSION:
            raise BusinessError(
                "OCR_FALLBACK_NOT_AVAILABLE", "No matching demo fallback is available.", 409
            )
        existing = self.repository.result(task.id)
        if existing is not None:
            if task.result_source == "fallback":
                return {**self.data(task), "reused": True}
            raise BusinessError("OCR_RESULT_ALREADY_EXISTS", "OCR task already has a result.", 409)
        match, _ = self._fallback_match(task)
        if match is None:
            raise BusinessError(
                "OCR_FALLBACK_NOT_AVAILABLE", "No matching demo fallback is available.", 409
            )
        validate(instance=match.payload, schema=schema_for(task.material_type))
        trigger_category = task.error_category or "provider_unavailable"
        trigger_code = task.error_code or "OCR_PROVIDER_UNAVAILABLE"
        result = OCRResult(
            id=new_uuid(),
            task_id=task.id,
            raw_response={
                "source": "fallback",
                "data_version": match.data_version,
                "matched_sha256": self._revision_hash(task),
            },
            validated_draft=match.payload["draft"],
        )
        self.session.add(result)
        self.session.flush()
        self.session.add_all(
            [
                OCRFieldResult(
                    id=new_uuid(),
                    result_id=result.id,
                    field_path=field["path"],
                    source_text=field.get("source_text"),
                    parsed_value=field.get("value"),
                    confidence=float(field["confidence"]),
                    uncertainty_reason=field.get("uncertainty_reason"),
                    source_region=field.get("source_region"),
                )
                for field in match.payload["fields"]
            ]
        )
        now = utc_now()
        fallback = OCRFallbackUse(
            id=new_uuid(),
            task_id=task.id,
            patient_id=task.patient_id,
            document_id=task.document_id,
            document_revision_id=task.document_revision_id,
            file_hash=self._revision_hash(task),
            material_type=task.material_type,
            data_version=match.data_version,
            trigger_category=trigger_category,
            trigger_code=trigger_code,
            selected_by_uid=self.account.uid,
            selected_at=now,
        )
        self.session.add(fallback)
        task.status = "pending_confirmation"
        task.result_source = "fallback"
        task.error_category = None
        task.error_code = None
        task.error_message = None
        task.finished_at = now
        task.updated_at = now
        try:
            self.session.commit()
            self.session.refresh(task)
        except IntegrityError:
            self.session.rollback()
            task = self.owned(task_id)
            if task.result_source != "fallback":
                raise
            return {**self.data(task), "reused": True}
        return {**self.data(task), "reused": False}

    def confirm_lab(self, task_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        task = self.owned(task_id)
        if task.material_type != "lab_report":
            raise BusinessError(
                "OCR_CONFIRM_TYPE_UNSUPPORTED",
                "This confirmation endpoint currently accepts laboratory reports only.",
                409,
            )
        result = self.repository.result(task.id)
        if result is None:
            raise BusinessError("OCR_RESULT_NOT_READY", "OCR result is not ready.", 409)
        if payload["result_id"] != result.id:
            raise BusinessError("OCR_RESULT_MISMATCH", "OCR result does not match the task.", 409)
        if payload["expected_revision_id"] != task.document_revision_id:
            raise BusinessError(
                "DOCUMENT_REVISION_MISMATCH",
                "The confirmation does not target the recognized document revision.",
                409,
            )

        canonical_payload = json.loads(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        if task.status == "confirmed":
            if result.confirmed_data != canonical_payload:
                raise BusinessError(
                    "OCR_ALREADY_CONFIRMED",
                    "The task was already confirmed with different data.",
                    409,
                )
            existing = self.labs.for_result(result.id)
            return self._confirmation_response(task, result, existing, reused=True)
        if task.status != "pending_confirmation":
            raise BusinessError(
                "OCR_TASK_NOT_CONFIRMABLE", "OCR task is not ready for confirmation.", 409
            )

        items: list[dict[str, Any]] = payload["items"]
        if not items:
            raise BusinessError(
                "LAB_CONFIRMATION_INVALID",
                "At least one laboratory item is required.",
                422,
                details={
                    "fields": [
                        FieldIssue(
                            "items", "LAB_ITEMS_REQUIRED", "至少需要一个化验项目。"
                        ).as_dict()
                    ],
                    "p0_evaluation": p0_evaluation(items),
                },
            )
        report_dates = {
            key: payload.get(key)
            for key in ("sample_date", "exam_date", "report_date", "visit_date")
        }
        normalized = []
        issues: list[FieldIssue] = []
        for index, item in enumerate(items):
            parsed, item_issues = normalize_lab_item(item, index, report_dates)
            issues.extend(item_issues)
            if parsed is not None:
                normalized.append((index, item, parsed))
        if issues:
            raise BusinessError(
                "LAB_CONFIRMATION_INVALID",
                "Resolve the highlighted laboratory fields before confirming.",
                422,
                details={
                    "fields": [issue.as_dict() for issue in issues],
                    "p0_evaluation": p0_evaluation(items),
                },
            )

        original_items = result.validated_draft.get("items", [])
        confirmed_at = utc_now()
        observations: list[LabObservation] = []
        for index, item, parsed in normalized:
            original = original_items[index] if index < len(original_items) else {}
            observation = LabObservation(
                id=new_uuid(),
                patient_id=task.patient_id,
                visit_id=payload.get("visit_id"),
                document_id=task.document_id,
                document_revision_id=task.document_revision_id,
                ocr_result_id=result.id,
                item_index=index,
                original_item_name=parsed.original_item_name,
                standard_metric_id=parsed.standard_metric_id,
                mapping_status=parsed.mapping_status,
                raw_value=parsed.raw_value,
                numeric_value=parsed.numeric_value,
                original_unit=parsed.original_unit,
                standard_unit=parsed.standard_unit,
                reference_range_raw=parsed.reference_range_raw,
                reference_lower=parsed.reference_lower,
                reference_upper=parsed.reference_upper,
                abnormal_status=parsed.abnormal_status,
                sample_date=parsed.sample_date,
                exam_date=parsed.exam_date,
                report_date=parsed.report_date,
                visit_date=parsed.visit_date,
                trend_date=parsed.trend_date,
                trend_date_source=parsed.trend_date_source,
                original_item_data=original,
                confirmed_item_data=item,
                confirmed_by_uid=self.account.uid,
                confirmed_at=confirmed_at,
                note=item.get("note"),
            )
            self.labs.add(observation)
            observations.append(observation)

        self._confirm_fields(result.id, items, payload)
        result.user_modified_data = canonical_payload
        result.confirmed_data = canonical_payload
        task.status = "confirmed"
        task.finished_at = task.finished_at or confirmed_at
        task.updated_at = confirmed_at
        mark_fallback_confirmed(self.session, task, uid=self.account.uid, confirmed_at=confirmed_at)
        self.session.commit()
        for observation in observations:
            self.session.refresh(observation)
        return self._confirmation_response(task, result, observations, reused=False)

    def _confirm_fields(
        self, result_id: str, items: list[dict[str, Any]], payload: dict[str, Any]
    ) -> None:
        values = {
            f"items.{index}.{field}": item.get(field)
            for index, item in enumerate(items)
            for field in (
                "name",
                "value",
                "unit",
                "reference_range",
                "sample_date",
                "exam_date",
                "report_date",
                "visit_date",
            )
        }
        values.update(
            {
                field: payload.get(field)
                for field in ("sample_date", "exam_date", "report_date", "visit_date")
            }
        )
        for field in self.repository.fields(result_id):
            if field.field_path not in values:
                continue
            submitted = values[field.field_path]
            field.user_value = submitted
            field.confirmation_status = (
                "accepted" if field.parsed_value == submitted else "corrected"
            )

    def _confirmation_response(
        self,
        task: OCRTask,
        result: OCRResult,
        observations: list[LabObservation],
        *,
        reused: bool,
    ) -> dict[str, Any]:
        return {
            "task_id": task.id,
            "result_id": result.id,
            "status": "confirmed",
            "reused": reused,
            "created_resource_ids": [item.id for item in observations],
            "confirmed_at": (
                None if not observations else observations[0].confirmed_at.isoformat()
            ),
            "observations": [lab_observation_data(item) for item in observations],
            "p0_evaluation": p0_evaluation(
                result.confirmed_data.get("items", []),
                result.validated_draft.get("items", []),
            ),
        }

    def retry(self, task_id: str) -> tuple[OCRTask, bool]:
        original = self.owned(task_id)
        if original.status not in {"failed", "timed_out"}:
            raise BusinessError("OCR_TASK_NOT_RETRYABLE", "OCR task cannot be retried.", 409)
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

    def list_lab_observations(self) -> list[dict[str, Any]]:
        return [lab_observation_data(item) for item in self.labs.list()]

    def lab_observation(self, observation_id: str) -> dict[str, Any]:
        observation = self.labs.get(observation_id)
        if observation is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Lab observation was not found.", 404)
        return lab_observation_data(observation)

    def _fallback_match(self, task: OCRTask) -> tuple[Any | None, str]:
        if task.status not in {"failed", "timed_out"}:
            return None, "task_not_failed"
        if task.error_category not in ALLOWED_FAILURE_CATEGORIES:
            return None, "failure_not_eligible"
        match = fallback_match(self._revision_hash(task), task.material_type, FALLBACK_DATA_VERSION)
        return (match, "exact_match" if match is not None else "file_not_registered")

    def _revision_hash(self, task: OCRTask) -> str:
        revision = self.documents.revision(task.document_id, task.document_revision_id)
        if revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Document revision was not found.", 404)
        return revision.file_hash.casefold()

    @staticmethod
    def _fallback_data(fallback: OCRFallbackUse) -> dict[str, Any]:
        return {
            "result_source": "fallback",
            "data_version": fallback.data_version,
            "trigger_reason": {
                "category": fallback.trigger_category,
                "code": fallback.trigger_code,
            },
            "selected_by_uid": fallback.selected_by_uid,
            "selected_at": fallback.selected_at.isoformat(),
            "confirmed_by_uid": fallback.confirmed_by_uid,
            "confirmed_at": (
                fallback.confirmed_at.isoformat() if fallback.confirmed_at is not None else None
            ),
        }

    @staticmethod
    def _key(*parts: str) -> str:
        return hashlib.sha256("\x1f".join(parts).encode()).hexdigest()
