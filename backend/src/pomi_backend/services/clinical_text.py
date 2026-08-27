"""Transactional confirmation of imaging text and outpatient OCR drafts."""

from __future__ import annotations

from datetime import date
from typing import Any

from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    ImagingReport,
    OCRResult,
    OCRTask,
    OutpatientRecord,
    UserAccount,
)
from pomi_backend.repositories import ClinicalTextRepository, OCRRepository, PatientRepository
from pomi_backend.schemas.clinical_text import (
    ClinicalTextConfirmRequest,
    ImagingTextConfirmation,
    OutpatientConfirmation,
)


def _record_data(record: ImagingReport | OutpatientRecord, task: OCRTask) -> dict[str, Any]:
    summary = (
        {"findings": record.findings_text, "impression": record.conclusion_text}
        if isinstance(record, ImagingReport)
        else {
            "diagnosis_summary": record.diagnosis_summary,
            "medical_advice": record.medical_advice,
        }
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
    }


class ClinicalTextConfirmationService:
    def __init__(self, session: Session, account: UserAccount) -> None:
        self.session = session
        self.account = account
        patient = PatientRepository(session).get_or_create(account.uid)
        self.patient_id = patient.patient_id
        self.ocr = OCRRepository(session, patient.patient_id)
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
        existing = self._existing(task, result)
        if existing is not None:
            return {**_record_data(existing, task), "reused": True}
        if task.status != "pending_confirmation":
            raise BusinessError(
                "OCR_TASK_NOT_CONFIRMABLE", "OCR task is not awaiting confirmation.", 409
            )
        confirmed = self._validate(task, payload.confirmed_data)
        self._validate_dates(confirmed)
        record = self._build_record(task, result, confirmed)
        result_id = result.id
        material_type = task.material_type
        try:
            if isinstance(record, ImagingReport):
                self.records.add_imaging(record)
            else:
                self.records.add_outpatient(record)
            result.user_modified_data = payload.confirmed_data
            result.confirmed_data = confirmed.model_dump(mode="json")
            decisions = {item.field_path: item for item in payload.field_confirmations}
            for field in self.ocr.fields(result.id):
                decision = decisions.get(field.field_path)
                if decision is not None:
                    field.user_value = decision.user_value
                    field.confirmation_status = {
                        "confirmed": "accepted",
                        "edited": "corrected",
                        "rejected": "rejected",
                    }[decision.confirmation_status]
                else:
                    value = payload.confirmed_data.get(field.field_path)
                    field.user_value = value
                    field.confirmation_status = (
                        "accepted" if value == field.parsed_value else "corrected"
                    )
            task.status = "confirmed"
            self.session.commit()
            self.session.refresh(record)
            return {**_record_data(record, task), "reused": False}
        except IntegrityError:
            self.session.rollback()
            existing = (
                self.records.imaging_by_result(result_id)
                if material_type == "imaging_text_report"
                else self.records.outpatient_by_result(result_id)
            )
            if existing is not None:
                return {**_record_data(existing, task), "reused": True}
            raise
        except Exception:
            self.session.rollback()
            raise

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
            raise BusinessError(
                "OCR_CONFIRMATION_INVALID",
                "Resolve the highlighted fields before confirmation.",
                422,
                details={
                    "field_errors": error.errors(
                        include_url=False,
                        include_input=False,
                        include_context=False,
                    )
                },
            ) from error

    @staticmethod
    def _validate_dates(confirmed: ImagingTextConfirmation | OutpatientConfirmation) -> None:
        dates = (
            [confirmed.examination_date, confirmed.report_date]
            if isinstance(confirmed, ImagingTextConfirmation)
            else [confirmed.visit_date]
        )
        invalid = [
            value for value in dates if value and (value.year < 1900 or value > date.today())
        ]
        if invalid:
            raise BusinessError(
                "OCR_CONFIRMATION_INVALID_DATE",
                "A clinical date is outside the supported range.",
                422,
                details={"field_errors": [{"type": "invalid_date"}]},
            )

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
            "confirmed_payload": confirmed.model_dump(mode="json"),
            "confirmed_by_uid": self.account.uid,
        }
        if isinstance(confirmed, ImagingTextConfirmation):
            return ImagingReport(
                **common,
                facility=confirmed.facility,
                examination_name=confirmed.examination_name,
                body_part=confirmed.body_part,
                modality=confirmed.modality,
                examination_date=confirmed.examination_date,
                report_date=confirmed.report_date,
                findings_text=confirmed.findings,
                conclusion_text=confirmed.impression,
            )
        return OutpatientRecord(
            **common,
            facility=confirmed.facility,
            department=confirmed.department,
            doctor_name=confirmed.doctor_name,
            visit_date=confirmed.visit_date,
            chief_complaint=confirmed.chief_complaint,
            diagnosis_summary=confirmed.diagnosis_summary,
            treatment_plan=confirmed.treatment_plan,
            medical_advice=confirmed.medical_advice,
        )
