"""Transactional confirmation of imaging text and outpatient OCR drafts."""

from __future__ import annotations

import json
from datetime import date
from typing import Any

from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import ImagingReport, OCRResult, OCRTask, OutpatientRecord, UserAccount
from pomi_backend.db.models.auth import utc_now
from pomi_backend.repositories import (
    ClinicalTextRepository,
    DocumentRepository,
    OCRRepository,
    PatientRepository,
)
from pomi_backend.schemas.clinical_text import (
    ClinicalTextConfirmRequest,
    ImagingTextConfirmation,
    OutpatientConfirmation,
)
from pomi_backend.services.ocr_fallback import mark_fallback_confirmed


def _record_data(
    record: ImagingReport | OutpatientRecord,
    task: OCRTask,
    *,
    reused: bool,
) -> dict[str, Any]:
    summary = (
        {"findings_text": record.findings_text, "conclusion_text": record.conclusion_text}
        if isinstance(record, ImagingReport)
        else {
            "diagnosis_summary": record.diagnosis_summary,
            "medical_advice": record.medical_advice,
        }
    )
    original = record.original_payload
    confirmed = record.confirmed_payload
    keys = sorted(set(original) | set(confirmed))
    corrected = sum(original.get(key) != confirmed.get(key) for key in keys)
    required = (
        ("findings_text", "conclusion_text")
        if isinstance(record, ImagingReport)
        else ("visit_date", "diagnosis_summary", "medical_advice")
    )
    return {
        "record_id": record.id,
        "task_id": task.id,
        "result_id": record.ocr_result_id,
        "created_resource_ids": [record.id],
        "reconciliation_required": False,
        "material_type": task.material_type,
        "document_id": record.document_id,
        "document_revision_id": record.document_revision_id,
        "ocr_result_id": record.ocr_result_id,
        "confirmed_at": record.confirmed_at.isoformat(),
        "summary": summary,
        "p0_evaluation": {
            "required_fields": len(required),
            "valid_required_fields": sum(bool(confirmed.get(key)) for key in required),
            "total_fields": len(keys),
            "corrected_fields": corrected,
            "exact_match_fields": len(keys) - corrected,
        },
        "reused": reused,
    }


class ClinicalTextConfirmationService:
    def __init__(
        self,
        session: Session,
        account: UserAccount,
        *,
        business_date: date,
    ) -> None:
        self.session = session
        self.account = account
        self.business_date = business_date
        patient = PatientRepository(session).get_or_create(account.uid)
        self.patient_id = patient.patient_id
        self.ocr = OCRRepository(session, patient.patient_id)
        self.documents = DocumentRepository(session, patient.patient_id)
        self.records = ClinicalTextRepository(session, patient.patient_id)

    def confirm(self, task_id: str, payload: ClinicalTextConfirmRequest) -> dict[str, Any]:
        task = self.ocr.get(task_id)
        if task is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR task was not found.", 404)
        if task.material_type not in {"imaging_text_report", "outpatient_record"}:
            raise BusinessError(
                "OCR_CONFIRMATION_TYPE_UNSUPPORTED",
                "This confirmation endpoint does not handle the material type.",
                409,
            )
        result = self.ocr.result(task.id)
        if result is None:
            raise BusinessError("OCR_RESULT_NOT_READY", "OCR result is not ready.", 409)
        if (
            payload.result_id != result.id
            or payload.expected_revision_id != task.document_revision_id
            or payload.document_type != task.material_type
        ):
            raise BusinessError(
                "OCR_CONFIRMATION_VERSION_CONFLICT",
                "The OCR result or document revision has changed.",
                409,
            )

        confirmed = self._validate(task, payload.confirmed_data)
        self._validate_dates(confirmed)
        canonical_payload = json.loads(
            json.dumps(payload.model_dump(mode="json"), ensure_ascii=False, sort_keys=True)
        )
        if task.status == "confirmed":
            return self._replay(task, result, canonical_payload)
        if task.status != "pending_confirmation":
            raise BusinessError(
                "OCR_TASK_NOT_CONFIRMABLE", "OCR task is not awaiting confirmation.", 409
            )
        document = self.documents.get(task.document_id)
        revision = self.documents.revision(task.document_id, task.document_revision_id)
        if document is None or revision is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR source revision was not found.", 404)

        decision_issues = self._decision_issues(payload, confirmed, result)
        if decision_issues:
            raise BusinessError(
                "OCR_CONFIRMATION_INVALID",
                "Resolve the highlighted fields before confirmation.",
                422,
                details={"fields": decision_issues},
            )

        if not self.ocr.claim_confirmation(task.id, now=utc_now()):
            self.session.rollback()
            current_task = self.ocr.get(task_id)
            current_result = self.ocr.result(task_id)
            if current_task is not None and current_result is not None:
                if current_task.status == "confirmed":
                    return self._replay(current_task, current_result, canonical_payload)
            raise BusinessError(
                "OCR_CONFIRMATION_IN_PROGRESS",
                "Another confirmation request is currently being processed.",
                409,
            )

        record = self._build_record(task, result, confirmed)
        try:
            if isinstance(record, ImagingReport):
                self.records.add_imaging(record)
            else:
                self.records.add_outpatient(record)
            result.user_modified_data = confirmed.model_dump(mode="json")
            result.confirmed_data = canonical_payload
            decisions = {item.field_path: item for item in payload.field_confirmations}
            final_values = confirmed.model_dump(mode="json")
            for field in self.ocr.fields(result.id):
                value = final_values.get(field.field_path)
                decision = decisions.get(field.field_path)
                field.user_value = value
                field.confirmation_status = (
                    "rejected"
                    if decision is not None and decision.confirmation_status == "rejected"
                    else "confirmed"
                    if value == field.parsed_value
                    else "edited"
                )
            finished_at = utc_now()
            task.status = "confirmed"
            task.finished_at = task.finished_at or finished_at
            task.updated_at = finished_at
            mark_fallback_confirmed(
                self.session,
                task,
                uid=self.account.uid,
                confirmed_at=record.confirmed_at,
            )
            self.session.commit()
            self.session.refresh(record)
            return _record_data(record, task, reused=False)
        except IntegrityError:
            self.session.rollback()
            current_task = self.ocr.get(task_id)
            current_result = self.ocr.result(task_id)
            if current_task is not None and current_result is not None:
                return self._replay(current_task, current_result, canonical_payload)
            raise
        except Exception:
            self.session.rollback()
            raise

    def _replay(
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
        existing = self._existing(task, result)
        if existing is None:
            raise BusinessError(
                "OCR_CONFIRMATION_INCOMPLETE",
                "The confirmed task has no matching formal record.",
                409,
            )
        return _record_data(existing, task, reused=True)

    def _existing(
        self, task: OCRTask, result: OCRResult
    ) -> ImagingReport | OutpatientRecord | None:
        if task.material_type == "imaging_text_report":
            return self.records.imaging_by_result(result.id)
        return self.records.outpatient_by_result(result.id)

    def _validate(
        self, task: OCRTask, data: dict[str, Any]
    ) -> ImagingTextConfirmation | OutpatientConfirmation:
        schema = (
            ImagingTextConfirmation
            if task.material_type == "imaging_text_report"
            else OutpatientConfirmation
        )
        try:
            return schema.model_validate(data)
        except ValidationError as error:
            fields = [
                {
                    "path": ".".join(str(part) for part in item["loc"]),
                    "code": "CLINICAL_FIELD_INVALID",
                    "message": item["msg"],
                }
                for item in error.errors(
                    include_url=False, include_input=False, include_context=False
                )
            ]
            raise BusinessError(
                "OCR_CONFIRMATION_INVALID",
                "Resolve the highlighted fields before confirmation.",
                422,
                details={"fields": fields},
            ) from error

    def _validate_dates(self, confirmed: ImagingTextConfirmation | OutpatientConfirmation) -> None:
        values = (
            {"examined_at": confirmed.examined_at, "reported_at": confirmed.reported_at}
            if isinstance(confirmed, ImagingTextConfirmation)
            else {"visit_date": confirmed.visit_date}
        )
        fields = [
            {
                "path": path,
                "code": "CLINICAL_DATE_OUT_OF_RANGE",
                "message": "日期必须在 1900-01-01 与服务器业务日期之间。",
            }
            for path, value in values.items()
            if value is not None and (value.year < 1900 or value > self.business_date)
        ]
        if fields:
            raise BusinessError(
                "OCR_CONFIRMATION_INVALID_DATE",
                "A clinical date is outside the supported range.",
                422,
                details={"fields": fields, "business_date": self.business_date.isoformat()},
            )

    @staticmethod
    def _required_fields(
        confirmed: ImagingTextConfirmation | OutpatientConfirmation,
    ) -> tuple[str, ...]:
        if isinstance(confirmed, ImagingTextConfirmation):
            return ("findings_text", "conclusion_text")
        return ("visit_date", "diagnosis_summary", "medical_advice")

    def _decision_issues(
        self,
        payload: ClinicalTextConfirmRequest,
        confirmed: ImagingTextConfirmation | OutpatientConfirmation,
        result: OCRResult,
    ) -> list[dict[str, str]]:
        final_values = confirmed.model_dump(mode="json")
        known_paths = {field.field_path for field in self.ocr.fields(result.id)}
        required = self._required_fields(confirmed)
        seen: set[str] = set()
        issues: list[dict[str, str]] = []
        for decision in payload.field_confirmations:
            code = message = None
            if decision.field_path in seen:
                code = "CLINICAL_FIELD_DECISION_DUPLICATE"
                message = "同一个字段不能提交多个确认决定。"
            elif decision.field_path not in known_paths:
                code = "CLINICAL_FIELD_DECISION_UNKNOWN"
                message = "字段不属于当前识别结果，请重新加载草稿。"
            elif decision.user_value != final_values.get(decision.field_path):
                code = "CLINICAL_FIELD_DECISION_VALUE_MISMATCH"
                message = "字段决定与最终确认值不一致。"
            elif decision.confirmation_status == "rejected" and decision.field_path in required:
                code = "CLINICAL_REQUIRED_FIELD_REJECTED"
                message = "关键字段不能在保存正式记录时标记为拒绝。"
            elif (
                decision.confirmation_status == "rejected"
                and final_values.get(decision.field_path) is not None
            ):
                code = "CLINICAL_REJECTED_FIELD_HAS_VALUE"
                message = "标记为拒绝的可选字段必须清空。"
            seen.add(decision.field_path)
            if code is not None and message is not None:
                issues.append({"path": decision.field_path, "code": code, "message": message})
        return issues

    def _build_record(
        self,
        task: OCRTask,
        result: OCRResult,
        confirmed: ImagingTextConfirmation | OutpatientConfirmation,
    ) -> ImagingReport | OutpatientRecord:
        common = {
            "patient_id": self.patient_id,
            "document_id": task.document_id,
            "document_revision_id": task.document_revision_id,
            "ocr_result_id": result.id,
            "original_payload": result.validated_draft,
            "confirmed_payload": confirmed.model_dump(mode="json"),
            "confirmed_by_uid": self.account.uid,
        }
        if isinstance(confirmed, ImagingTextConfirmation):
            return ImagingReport(**common, **confirmed.model_dump())
        return OutpatientRecord(**common, **confirmed.model_dump())
