"""Authenticated OCR task creation, lookup, and manual retry service."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    LabObservation,
    Medication,
    MedicationEvent,
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
from pomi_backend.schemas.ocr_recognize import OCRResultConfirmRequest
from pomi_backend.services.lab_rules import (
    FieldIssue,
    normalize_lab_item,
    p0_evaluation,
    parse_number,
)
from pomi_backend.services.medications import instruction_data, medication_data
from pomi_backend.services.ocr_prompts import PROMPT_VERSION, SCHEMA_VERSION
from pomi_backend.services.orders import standard_drug_id
from pomi_backend.services.watermarks import (
    ASSET_TYPE,
    WATERMARK_VERSION,
    display_asset_data,
)


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


def normalize_algorithm_payload(payload: dict[str, Any], original_file_name: str) -> dict[str, Any]:
    """Normalize the algorithm's flat response and the legacy worker envelope."""
    evidence = payload.get("evidence")
    if isinstance(payload.get("draft"), dict):
        draft = payload["draft"]
        evidence = payload.get("fields")
        payload = {
            "hospital": draft.get("hospital") or draft.get("hospital_name"),
            "department": draft.get("department") or draft.get("department_name"),
            "visit_date": draft.get("visit_date") or draft.get("prescribed_at"),
            "diagnosis_summary": draft.get("diagnosis_summary"),
            "medical_advice": draft.get("medical_advice") or draft.get("treatment_plan"),
            "examinations": draft.get("examinations")
            or [
                {
                    "item_name": item.get("item_name"),
                    "value": item.get("raw_value")
                    if item.get("raw_value") is not None
                    else item.get("numeric_value"),
                    "unit": item.get("raw_unit") or item.get("normalized_unit"),
                    "reference_range": item.get("reference_range_text"),
                }
                for item in draft.get("items", [])
                if isinstance(item, dict)
            ],
            "medication_suggestions": draft.get("medication_suggestions")
            or draft.get("orders", []),
        }
        # Imaging text reports and outpatient records carry material-specific
        # fields that must survive normalization; the generic envelope above
        # drops them, so forward the whole draft's extra keys verbatim.
        _list_keys = {"examinations", "items", "orders", "medication_suggestions"}
        for key, value in draft.items():
            if key not in payload and key not in _list_keys:
                payload[key] = value
    payload["original_file_name"] = original_file_name
    if evidence is not None:
        payload["evidence"] = evidence
    payload.setdefault("examinations", [])
    payload.setdefault("medication_suggestions", [])
    return payload


def sync_result_data(task: OCRTask, result: OCRResult) -> dict[str, Any]:
    return {
        **result.validated_draft,
        "ocr_task_id": task.id,
        "ocr_result_id": result.id,
        "document_id": task.document_id,
        "document_revision_id": task.document_revision_id,
        "material_type": task.material_type,
        "result_source": task.result_source,
    }


def deduplication_key(*parts: str) -> str:
    return hashlib.sha256("\x1f".join(parts).encode()).hexdigest()


def _source_item(draft: dict[str, Any], key: str, index: int) -> dict[str, Any]:
    values = draft.get(key, [])
    if isinstance(values, list) and 0 <= index < len(values) and isinstance(values[index], dict):
        return values[index]
    return {}


def _dosage_parts(value: str | None) -> tuple[Decimal | None, str | None]:
    if value is None or not value.strip():
        return None, None
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*([^\d\s]+)\s*", value)
    if match is None:
        return None, None
    try:
        return Decimal(match.group(1)), match.group(2)
    except InvalidOperation:
        return None, None


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
        "original_item_data": observation.original_item_data,
        "confirmed_item_data": observation.confirmed_item_data,
        "confirmed_by_uid": observation.confirmed_by_uid,
        "confirmed_at": observation.confirmed_at.isoformat(),
        "note": observation.note,
    }


class OCRTaskService:
    def __init__(
        self,
        session: Session,
        account: UserAccount,
        *,
        model_name: str,
        business_date: date,
        storage_root: Path,
    ) -> None:
        self.session = session
        self.account = account
        self.model_name = model_name
        self.business_date = business_date
        self.storage_root = storage_root
        self.patient = PatientRepository(session).get_or_create(account.uid)
        self.repository = OCRRepository(session, self.patient.patient_id)
        self.documents = DocumentRepository(session, self.patient.patient_id)
        self.labs = LabObservationRepository(session, self.patient.patient_id)

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
        document = self.documents.get(task.document_id)
        revision = self.documents.revision(task.document_id, task.document_revision_id)
        source = None
        if document is not None and revision is not None:
            display_asset = self.documents.display_asset(
                document.id,
                revision.id,
                asset_type=ASSET_TYPE,
                watermark_version=WATERMARK_VERSION,
            )
            source = {
                "document_id": document.id,
                "document_revision_id": revision.id,
                "original_file_name": document.original_file_name,
                "mime_type": revision.mime_type,
                "revision_number": revision.revision_number,
                "file_endpoint": (f"/api/documents/{document.id}/revisions/{revision.id}/file"),
                "display_asset": display_asset_data(display_asset),
            }
        return result_data(
            result,
            self.repository.fields(result.id),
            source_document=source,
        )

    def confirm_result(self, result_id: str, payload: OCRResultConfirmRequest) -> dict[str, Any]:
        result = self.repository.result_by_id(result_id)
        if result is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR result was not found.", 404)
        task = self.owned(result.task_id)
        canonical = payload.model_dump(mode="json")
        if result.confirmed_data is not None:
            if result.confirmed_data.get("request") != canonical:
                raise BusinessError(
                    "OCR_ALREADY_CONFIRMED",
                    "The OCR result was already confirmed with different data.",
                    409,
                )
            return {**result.confirmed_data["created"], "reused": True}
        if task.status != "pending_confirmation":
            raise BusinessError(
                "OCR_RESULT_NOT_CONFIRMABLE", "OCR result is not pending confirmation.", 409
            )
        if not payload.examinations and not payload.medication_suggestions:
            raise BusinessError(
                "OCR_CONFIRMATION_EMPTY", "At least one health item must be confirmed.", 422
            )

        report_dates = {
            "sample_date": None,
            "exam_date": None,
            "report_date": None,
            "visit_date": payload.visit_date,
        }
        normalized_labs = []
        issues: list[FieldIssue] = []
        source_examinations = result.validated_draft.get("examinations", [])
        if not isinstance(source_examinations, list):
            source_examinations = []
        for index, item in enumerate(payload.examinations):
            if item.source_index >= len(source_examinations):
                issues.append(
                    FieldIssue(
                        f"examinations.{index}.source_index",
                        "OCR_SOURCE_INDEX_INVALID",
                        "来源检查项目不存在，请重新加载识别结果。",
                    )
                )
            normalized, item_issues = normalize_lab_item(
                {
                    "name": item.item_name,
                    "value": item.value,
                    "unit": item.unit,
                    "reference_range": item.reference_range,
                },
                index,
                report_dates,
            )
            issues.extend(item_issues)
            if normalized is not None:
                normalized_labs.append((item, normalized))

        medication_values = []
        source_medications = result.validated_draft.get("medication_suggestions", [])
        if not isinstance(source_medications, list):
            source_medications = []
        for index, item in enumerate(payload.medication_suggestions):
            if item.source_index >= len(source_medications):
                issues.append(
                    FieldIssue(
                        f"medication_suggestions.{index}.source_index",
                        "OCR_SOURCE_INDEX_INVALID",
                        "来源用药建议不存在，请重新加载识别结果。",
                    )
                )
            identifier = standard_drug_id(item.drug_name.strip())
            # 未映射药名不再硬阻塞入库：标准词库未收录的药品（如地屈孕酮、肌醇等）
            # 仍可确认，仅保留 standard_drug_id=None 供后续人工复核。
            dosage_value, dosage_unit = _dosage_parts(item.dosage)
            # 剂量缺空或无法解析为「数值+单位」时不再硬阻塞：保留原始文本，
            # 由用户后续在用药详情中修正，避免「确认并入库」因剂量格式失败。
            if item.dosage and (dosage_value is None or dosage_unit is None):
                dosage_value = None
                dosage_unit = None
            medication_values.append((item, identifier, dosage_value, dosage_unit))
        if issues:
            raise BusinessError(
                "OCR_CONFIRMATION_INVALID",
                "Resolve the highlighted fields before importing.",
                422,
                details={"fields": [issue.as_dict() for issue in issues]},
            )
        if not self.repository.claim_confirmation(task.id, now=utc_now()):
            self.session.rollback()
            raise BusinessError(
                "OCR_CONFIRMATION_IN_PROGRESS",
                "Another confirmation request is being processed.",
                409,
            )

        confirmed_at = utc_now()
        observations: list[LabObservation] = []
        medications: list[Medication] = []
        try:
            for item, normalized in normalized_labs:
                observation = LabObservation(
                    id=new_uuid(),
                    patient_id=self.patient.patient_id,
                    document_id=task.document_id,
                    document_revision_id=task.document_revision_id,
                    ocr_result_id=result.id,
                    item_index=item.source_index,
                    original_item_name=normalized.original_item_name,
                    standard_metric_id=normalized.standard_metric_id,
                    mapping_status=normalized.mapping_status,
                    raw_value=normalized.raw_value,
                    numeric_value=normalized.numeric_value,
                    original_unit=normalized.original_unit,
                    standard_unit=normalized.standard_unit,
                    reference_range_raw=normalized.reference_range_raw,
                    reference_lower=normalized.reference_lower,
                    reference_upper=normalized.reference_upper,
                    abnormal_status=normalized.abnormal_status,
                    sample_date=normalized.sample_date,
                    exam_date=normalized.exam_date,
                    report_date=normalized.report_date,
                    visit_date=normalized.visit_date,
                    trend_date=normalized.trend_date,
                    trend_date_source=normalized.trend_date_source,
                    original_item_data=_source_item(
                        result.validated_draft, "examinations", item.source_index
                    ),
                    confirmed_item_data=item.model_dump(mode="json"),
                    confirmed_by_uid=self.account.uid,
                    confirmed_at=confirmed_at,
                    note=item.note,
                )
                self.labs.add(observation)
                observations.append(observation)
            for item, identifier, dosage_value, dosage_unit in medication_values:
                medication = Medication(
                    id=new_uuid(),
                    patient_id=self.patient.patient_id,
                    drug_name=item.drug_name.strip(),
                    standard_drug_id=identifier,
                    source_category=item.source_category,
                    dosage_value=dosage_value,
                    dosage_unit=dosage_unit,
                    frequency=item.frequency,
                    start_date=item.start_date or payload.visit_date,
                    status="active",
                    idempotency_key=f"ocr:{result.id}:{item.source_index}",
                )
                self.session.add(medication)
                self.session.flush()
                self.session.add(
                    MedicationEvent(
                        id=new_uuid(),
                        patient_id=self.patient.patient_id,
                        medication_id=medication.id,
                        event_type="created",
                        event_date=item.start_date or payload.visit_date or self.business_date,
                        new_instruction=instruction_data(medication),
                        source_type="medical_order",
                        source_document_id=task.document_id,
                        acted_by_uid=self.account.uid,
                        note=item.instruction,
                    )
                )
                medications.append(medication)
            created = {
                "ocr_result_id": result.id,
                "status": "confirmed",
                "observations": [lab_observation_data(item) for item in observations],
                "medications": [medication_data(item) for item in medications],
            }
            result.user_modified_data = canonical
            result.confirmed_data = {"request": canonical, "created": created}
            task.status = "confirmed"
            task.finished_at = task.finished_at or confirmed_at
            task.updated_at = confirmed_at
            self.session.commit()
            return {**created, "reused": False}
        except Exception:
            self.session.rollback()
            raise

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
            return self._replay_confirmation(task, result, canonical_payload)
        if task.status != "pending_confirmation":
            raise BusinessError(
                "OCR_TASK_NOT_CONFIRMABLE", "OCR task is not ready for confirmation.", 409
            )

        document = self.documents.get(task.document_id)
        revision = self.documents.revision(task.document_id, task.document_revision_id)
        if document is None or revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR source revision was not found.", 404)

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
        original_items = result.validated_draft.get("items", [])
        if not isinstance(original_items, list):
            original_items = []
        normalized = []
        issues: list[FieldIssue] = []
        used_source_indices: set[int] = set()
        next_added_index = len(original_items)
        for index, item in enumerate(items):
            parsed, item_issues = normalize_lab_item(item, index, report_dates)
            issues.extend(item_issues)
            source_index = item.get("source_index")
            if source_index is None:
                source_index = next_added_index
                next_added_index += 1
            elif source_index >= len(original_items):
                issues.append(
                    FieldIssue(
                        f"items.{index}.source_index",
                        "LAB_SOURCE_INDEX_INVALID",
                        "来源项目不存在，请重新加载识别草稿。",
                    )
                )
            if source_index in used_source_indices:
                issues.append(
                    FieldIssue(
                        f"items.{index}.source_index",
                        "LAB_SOURCE_INDEX_DUPLICATE",
                        "同一个来源项目不能重复确认。",
                    )
                )
            used_source_indices.add(source_index)
            if parsed is not None:
                normalized.append((source_index, item, parsed))
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

        confirmation_started_at = utc_now()
        if not self.repository.claim_confirmation(task.id, now=confirmation_started_at):
            self.session.rollback()
            current_task = self.owned(task_id)
            current_result = self.repository.result(current_task.id)
            if current_result is None:
                raise BusinessError("OCR_RESULT_NOT_READY", "OCR result is not ready.", 409)
            if current_task.status == "confirmed":
                return self._replay_confirmation(current_task, current_result, canonical_payload)
            raise BusinessError(
                "OCR_CONFIRMATION_IN_PROGRESS",
                "Another confirmation request is currently being processed.",
                409,
            )

        confirmed_at = utc_now()
        observations: list[LabObservation] = []
        for source_index, item, parsed in normalized:
            original = original_items[source_index] if source_index < len(original_items) else {}
            observation = LabObservation(
                id=new_uuid(),
                patient_id=task.patient_id,
                visit_id=payload.get("visit_id"),
                document_id=task.document_id,
                document_revision_id=task.document_revision_id,
                ocr_result_id=result.id,
                item_index=source_index,
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

        self._confirm_fields(
            result.id,
            normalized,
            payload,
            original_item_count=len(original_items),
        )
        result.user_modified_data = canonical_payload
        result.confirmed_data = canonical_payload
        task.status = "confirmed"
        task.finished_at = task.finished_at or confirmed_at
        task.updated_at = confirmed_at
        self.session.commit()
        for observation in observations:
            self.session.refresh(observation)
        return self._confirmation_response(task, result, observations, reused=False)

    def _replay_confirmation(
        self,
        task: OCRTask,
        result: OCRResult,
        canonical_payload: dict[str, Any],
    ) -> dict[str, Any]:
        if result.confirmed_data != canonical_payload:
            raise BusinessError(
                "OCR_ALREADY_CONFIRMED",
                "The task was already confirmed with different data.",
                409,
            )
        existing = self.labs.for_result(result.id)
        return self._confirmation_response(task, result, existing, reused=True)

    def _confirm_fields(
        self,
        result_id: str,
        normalized: list[tuple[int, dict[str, Any], Any]],
        payload: dict[str, Any],
        *,
        original_item_count: int,
    ) -> None:
        values: dict[str, Any] = {}
        confirmed_source_indices: set[int] = set()
        for source_index, item, parsed in normalized:
            confirmed_source_indices.add(source_index)
            raw_numeric = parse_number(item.get("value"))
            values.update(
                {
                    f"items.{source_index}.item_name": item.get("name"),
                    f"items.{source_index}.raw_value": item.get("value"),
                    f"items.{source_index}.numeric_value": (
                        None if raw_numeric is None else float(raw_numeric)
                    ),
                    f"items.{source_index}.raw_unit": item.get("unit"),
                    f"items.{source_index}.normalized_unit": parsed.standard_unit,
                    f"items.{source_index}.reference_range_text": item.get("reference_range"),
                    f"items.{source_index}.reference_low": (
                        None if parsed.reference_lower is None else float(parsed.reference_lower)
                    ),
                    f"items.{source_index}.reference_high": (
                        None if parsed.reference_upper is None else float(parsed.reference_upper)
                    ),
                }
            )
        values.update(
            {
                field: payload.get(field)
                for field in ("sample_date", "exam_date", "report_date", "visit_date")
            }
        )
        for field in self.repository.fields(result_id):
            item_path = field.field_path.split(".", 2)
            if (
                len(item_path) == 3
                and item_path[0] == "items"
                and item_path[1].isdigit()
                and int(item_path[1]) < original_item_count
                and int(item_path[1]) not in confirmed_source_indices
            ):
                field.user_value = None
                field.confirmation_status = "rejected"
                continue
            submitted = values.get(field.field_path, field.parsed_value)
            field.user_value = submitted
            field.confirmation_status = "confirmed" if field.parsed_value == submitted else "edited"

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
                self._lab_draft_items(result.validated_draft),
            ),
        }

    @staticmethod
    def _lab_draft_items(draft: dict[str, Any]) -> list[dict[str, Any]]:
        raw_items = draft.get("items", [])
        if not isinstance(raw_items, list):
            return []
        return [
            {
                "source_index": index,
                "name": item.get("item_name") or item.get("name"),
                "value": (
                    item.get("raw_value")
                    if item.get("raw_value") is not None
                    else item.get("numeric_value", item.get("value"))
                ),
                "unit": item.get("raw_unit") or item.get("normalized_unit") or item.get("unit"),
            }
            for index, item in enumerate(raw_items)
            if isinstance(item, dict)
        ]

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

    def list_lab_observations(self) -> list[dict[str, Any]]:
        return [lab_observation_data(item) for item in self.labs.list()]

    def lab_observation(self, observation_id: str) -> dict[str, Any]:
        observation = self.labs.get(observation_id)
        if observation is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Lab observation was not found.", 404)
        return lab_observation_data(observation)

    @staticmethod
    def _key(*parts: str) -> str:
        return deduplication_key(*parts)
