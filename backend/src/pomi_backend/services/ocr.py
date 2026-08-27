"""OCR task API orchestration, schema validation, and confirmation persistence."""

from __future__ import annotations

import json
from collections.abc import Iterable
from datetime import date
from functools import lru_cache
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker
from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.config import Settings
from pomi_backend.db.models import (
    ImagingReport,
    LabObservation,
    MedicalOrder,
    OcrFieldResult,
    OcrResult,
    OcrTask,
    OutpatientRecord,
    UserAccount,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.schemas.ocr import OcrConfirmRequest, OcrTaskCreate
from pomi_backend.services.documents import DocumentService
from pomi_backend.services.health_records import HealthRecordService

SCHEMA_NAMES = {
    "lab_report": "lab-draft.schema.json",
    "medical_order": "medical-order-draft.schema.json",
    "imaging_text_report": "imaging-text-draft.schema.json",
    "outpatient_record": "outpatient-record-draft.schema.json",
}


@lru_cache
def validator_for(document_type: str) -> Draft202012Validator:
    file_name = SCHEMA_NAMES.get(document_type)
    if file_name is None:
        raise BusinessError("SCHEMA_VALIDATION_FAILED", "Unsupported document type.", 422)
    root = Path(__file__).resolve().parents[4] / "contracts" / "json-schemas"
    schema = json.loads((root / file_name).read_text(encoding="utf-8"))
    return Draft202012Validator(schema, format_checker=FormatChecker())


def validate_draft(document_type: str, value: dict[str, Any]) -> None:
    errors = sorted(
        validator_for(document_type).iter_errors(value), key=lambda error: list(error.path)
    )
    if errors:
        details = {
            "fields": [
                {
                    "path": ".".join(str(part) for part in error.path),
                    "message": error.message,
                }
                for error in errors[:20]
            ]
        }
        raise BusinessError(
            "SCHEMA_VALIDATION_FAILED",
            "OCR data does not match the document contract.",
            422,
            details=details,
        )


def flatten_fields(value: Any, prefix: str = "") -> Iterable[tuple[str, Any]]:
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else key
            if isinstance(child, (dict, list)):
                yield from flatten_fields(child, path)
            else:
                yield path, child
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from flatten_fields(child, f"{prefix}[{index}]")


def task_data(task: OcrTask) -> dict[str, Any]:
    return {
        "id": task.id,
        "document_id": task.document_id,
        "document_revision_id": task.document_revision_id,
        "document_type": task.document_type,
        "task_status": task.task_status,
        "attempt_count": task.attempt_count,
        "max_attempts": task.max_attempts,
        "queued_at": task.queued_at.isoformat(),
        "started_at": task.started_at.isoformat() if task.started_at else None,
        "finished_at": task.finished_at.isoformat() if task.finished_at else None,
        "processing_ms": task.processing_ms,
        "error_code": task.error_code,
        "error_message": task.error_message,
        "result_source": task.result_source,
        "progress": task.progress,
    }


def draft_result_data(
    task: OcrTask, result: OcrResult, fields: list[OcrFieldResult]
) -> dict[str, Any]:
    return {
        "result_id": result.id,
        "task_id": task.id,
        "document_type": task.document_type,
        "validation_status": result.validation_status,
        "critical_error": result.critical_error,
        "result_source": task.result_source,
        "validation_errors": [
            error.get("message", str(error)) for error in result.validation_errors_json
        ],
        "fields": [
            {
                "field_path": field.field_path,
                "raw_text": field.raw_text,
                "parsed_value": field.parsed_value,
                "confidence": field.confidence,
                "uncertainty_reason": field.uncertainty_reason,
                "source_region": field.source_region,
                "user_value": field.user_value,
                "confirmation_status": field.confirmation_status,
            }
            for field in fields
        ],
        "draft": result.parsed_result_json,
    }


class OcrService:
    def __init__(self, session: Session, account: UserAccount, settings: Settings) -> None:
        self.session = session
        self.account = account
        self.settings = settings
        self.health = HealthRecordService(session, account)
        self.documents = DocumentService(session, account, settings.storage_root)

    def owned_task(self, task_id: str) -> OcrTask:
        task = self.session.scalar(
            select(OcrTask).where(
                OcrTask.id == task_id,
                OcrTask.patient_id == self.health.profile().patient_id,
            )
        )
        if task is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR task was not found.", 404)
        return task

    def create(self, payload: OcrTaskCreate, idempotency_key: str) -> OcrTask:
        existing = self.session.scalar(
            select(OcrTask).where(
                OcrTask.created_by_uid == self.account.uid,
                OcrTask.idempotency_key == idempotency_key,
            )
        )
        if existing is not None:
            return existing
        document = self.documents.owned_document(payload.document_id)
        revision_ids = {revision.id for revision in self.documents.revisions(document.id)}
        if payload.document_revision_id not in revision_ids:
            raise BusinessError("RESOURCE_NOT_FOUND", "Document revision was not found.", 404)
        if (
            not payload.force_new_attempt
            and payload.document_revision_id != document.current_revision_id
        ):
            raise BusinessError(
                "RESOURCE_VERSION_CONFLICT", "OCR must use the current revision.", 409
            )
        task = OcrTask(
            patient_id=document.patient_id,
            document_id=document.id,
            document_revision_id=payload.document_revision_id,
            document_type=document.document_type,
            model_name=self.settings.qwen_model
            if self.settings.ocr_mode == "qwen"
            else "pomi-mock",
            prompt_key=f"{document.document_type}:p0-v1",
            max_attempts=self.settings.ocr_max_attempts,
            idempotency_key=idempotency_key,
            created_by_uid=self.account.uid,
        )
        document.upload_status = "processing"
        self.session.add(task)
        self.session.commit()
        self.session.refresh(task)
        return task

    def result(self, task_id: str) -> tuple[OcrTask, OcrResult, list[OcrFieldResult]]:
        task = self.owned_task(task_id)
        result = self.session.scalar(select(OcrResult).where(OcrResult.ocr_task_id == task.id))
        if result is None:
            raise BusinessError("OCR_RESULT_NOT_READY", "OCR result is not ready.", 409)
        fields = list(
            self.session.scalars(
                select(OcrFieldResult)
                .where(OcrFieldResult.ocr_result_id == result.id)
                .order_by(OcrFieldResult.field_path)
            )
        )
        return task, result, fields

    def confirm(self, task_id: str, payload: OcrConfirmRequest) -> dict[str, Any]:
        task, result, fields = self.result(task_id)
        document = self.documents.owned_document(task.document_id)
        if result.id != payload.result_id or task.document_type != payload.document_type:
            raise BusinessError("RESOURCE_VERSION_CONFLICT", "OCR result does not match.", 409)
        if document.current_revision_id != payload.expected_revision_id:
            raise BusinessError(
                "RESOURCE_VERSION_CONFLICT", "The document revision has changed.", 409
            )
        if task.task_status == "confirmed" or result.confirmed_at is not None:
            return self._confirmation_data(task, result, self._formal_resource_ids(result.id))
        validate_draft(task.document_type, payload.confirmed_data)

        confirmations = {item.field_path: item for item in payload.field_confirmations}
        if not payload.confirm_all:
            missing = [
                field.field_path for field in fields if field.field_path not in confirmations
            ]
            if missing:
                raise BusinessError(
                    "CRITICAL_FIELD_MISSING",
                    "Every OCR field must be reviewed.",
                    422,
                    details={"fields": missing},
                )
        confirmed_at = utc_now()
        for field in fields:
            confirmation = confirmations.get(field.field_path)
            field.confirmation_status = (
                confirmation.confirmation_status if confirmation else "confirmed"
            )
            field.user_value = confirmation.user_value if confirmation else field.parsed_value
            field.confirmed_by_uid = self.account.uid
            field.confirmed_at = confirmed_at

        resource_ids = self._persist_confirmed(task, result, payload.confirmed_data, confirmed_at)
        result.confirmed_result_json = payload.confirmed_data
        result.confirmed_by_uid = self.account.uid
        result.confirmed_at = confirmed_at
        task.task_status = "confirmed"
        task.finished_at = confirmed_at
        document.upload_status = "ready"
        self.session.commit()
        return self._confirmation_data(task, result, resource_ids)

    @staticmethod
    def _confirmation_data(
        task: OcrTask, result: OcrResult, resource_ids: list[str]
    ) -> dict[str, Any]:
        return {
            "task_id": task.id,
            "result_id": result.id,
            "created_resource_ids": resource_ids,
            "confirmed_at": result.confirmed_at.isoformat() if result.confirmed_at else None,
            "reconciliation_required": task.document_type == "medical_order",
        }

    def _formal_resource_ids(self, result_id: str) -> list[str]:
        identifiers: list[str] = []
        for model in (LabObservation, MedicalOrder, ImagingReport, OutpatientRecord):
            identifiers.extend(
                self.session.scalars(select(model.id).where(model.ocr_result_id == result_id))
            )
        return identifiers

    def _persist_confirmed(
        self,
        task: OcrTask,
        result: OcrResult,
        value: dict[str, Any],
        confirmed_at,
    ) -> list[str]:
        created: list[str] = []
        common = {
            "patient_id": task.patient_id,
            "document_id": task.document_id,
            "ocr_result_id": result.id,
            "confirmed_by_uid": self.account.uid,
            "confirmed_at": confirmed_at,
        }
        if task.document_type == "lab_report":
            for item in value["items"]:
                record = LabObservation(
                    **common,
                    item_name=item["item_name"],
                    item_code=item.get("item_code"),
                    raw_value=item["raw_value"],
                    numeric_value=item.get("numeric_value"),
                    raw_unit=item.get("raw_unit"),
                    normalized_unit=item.get("normalized_unit"),
                    reference_range_text=item.get("reference_range_text"),
                    reference_low=item.get("reference_low"),
                    reference_high=item.get("reference_high"),
                    sample_date=_date(value.get("sample_date")),
                    report_date=_date(value.get("report_date")),
                )
                self.session.add(record)
                self.session.flush()
                created.append(record.id)
        elif task.document_type == "medical_order":
            for item in value["orders"]:
                record = MedicalOrder(
                    **common,
                    source_text=item["source_text"],
                    drug_name=item["drug_name"],
                    normalized_drug_name=item.get("normalized_drug_name")
                    or item["drug_name"].casefold(),
                    specification=item.get("specification"),
                    dosage_text=item.get("dosage_text"),
                    dosage_value=item.get("dosage_value"),
                    dosage_unit=item.get("dosage_unit"),
                    frequency=item.get("frequency"),
                    duration=item.get("duration"),
                    route=item.get("route"),
                    instruction=item.get("instruction"),
                    prescribed_at=_date(value.get("prescribed_at")),
                )
                self.session.add(record)
                self.session.flush()
                created.append(record.id)
        elif task.document_type == "imaging_text_report":
            record = ImagingReport(
                **common,
                examination_name=value.get("examination_name"),
                body_part=value.get("body_part"),
                examination_method=value.get("examination_method"),
                findings_text=value["findings_text"],
                conclusion_text=value["conclusion_text"],
                examined_at=_date(value.get("examined_at")),
                reported_at=_date(value.get("reported_at")),
            )
            self.session.add(record)
            self.session.flush()
            created.append(record.id)
        else:
            record = OutpatientRecord(
                **common,
                hospital_name=value.get("hospital_name"),
                department_name=value.get("department_name"),
                doctor_name=value.get("doctor_name"),
                visit_date=_date(value["visit_date"]),
                chief_complaint=value.get("chief_complaint") or "",
                diagnosis_summary=value["diagnosis_summary"],
                treatment_plan=value["treatment_plan"],
                medical_advice=value.get("medical_advice"),
            )
            self.session.add(record)
            self.session.flush()
            created.append(record.id)
        return created


def _date(value: str | None) -> date | None:
    return date.fromisoformat(value) if value else None
