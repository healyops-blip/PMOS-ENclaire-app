"""Authenticated OCR task API; processing is delegated to a separate worker."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, File, Form, Header, Request, UploadFile, status
from jsonschema import ValidationError
from pydantic import BaseModel, ConfigDict, Field

from pomi_backend.api.business import BusinessError, success
from pomi_backend.api.dependencies import (
    ClinicalTextConfirmationServiceDependency,
    CurrentAccount,
    DatabaseSession,
    MedicalOrderServiceDependency,
    OCRTaskServiceDependency,
)
from pomi_backend.config import DEFAULT_OCR_MODEL
from pomi_backend.repositories import DocumentRepository
from pomi_backend.schemas.clinical_text import ClinicalTextConfirmRequest
from pomi_backend.schemas.ocr_recognize import OCRRecognizeData
from pomi_backend.schemas.orders import MedicalOrderConfirmation
from pomi_backend.services.document_storage import private_path
from pomi_backend.services.documents import DocumentService
from pomi_backend.services.ocr import task_data
from pomi_backend.services.ocr_provider import (
    OCRProviderError,
    OCRProviderRequest,
    Qwen3VLOCRProvider,
)
from pomi_backend.services.ocr_validation import validate_provider_payload
from pomi_backend.services.orders import medical_order_data, medical_order_p0

router = APIRouter(prefix="/api/ocr/tasks", tags=["ocr"])

sync_router = APIRouter(prefix="/api/ocr", tags=["ocr"])


@sync_router.post("/recognize")
def recognize(
    request: Request,
    session: DatabaseSession,
    account: CurrentAccount,
    service: OCRTaskServiceDependency,
    file: Annotated[UploadFile, File()],
    material_type: Annotated[str, Form()] = "outpatient_record",
    prompt_version: Annotated[str, Form()] = "pomi-ocr-v1",
    idempotency_key: Annotated[str, Header(alias="Idempotency-Key")] = "",
    consent_version: Annotated[
        str | None, Header(alias="X-External-Processing-Consent-Version")
    ] = None,
) -> dict:
    allowed = {"lab_report", "medical_order", "imaging_text_report", "outpatient_record"}
    if material_type not in allowed:
        raise BusinessError("OCR_MATERIAL_TYPE_INVALID", "Unsupported OCR material type.", 422)
    if prompt_version != "pomi-ocr-v1":
        raise BusinessError("OCR_PROMPT_VERSION_INVALID", "Unsupported OCR prompt version.", 422)
    if not consent_version:
        raise BusinessError(
            "EXTERNAL_PROCESSING_CONSENT_REQUIRED",
            "External OCR processing consent is required.",
            409,
        )
    if not idempotency_key:
        raise BusinessError("IDEMPOTENCY_KEY_REQUIRED", "Idempotency-Key is required.", 422)
    settings = request.app.state.settings
    document = DocumentService(session, account, settings.storage_root).upload(
        file,
        document_type=material_type,
        idempotency_key=idempotency_key,
        processing_notice_version=consent_version,
    )
    revision = DocumentRepository(
        session, DocumentService(session, account, settings.storage_root).patient.patient_id
    ).revision(document.id, document.current_revision_id)
    if revision is None:
        raise BusinessError("OCR_FILE_NOT_FOUND", "The uploaded file is unavailable.", 404)
    task, _ = service.create(document.id, revision.id)
    existing = service.repository.result(task.id)
    if existing is not None:
        return success(
            request,
            _recognize_response(service, task, existing, document.original_file_name),
        )
    task = service.claim_synchronous(
        task,
        lease_seconds=settings.ocr_request_timeout_seconds + 30,
    )
    provider = Qwen3VLOCRProvider(
        api_base_url=settings.ocr_api_base_url,
        api_key=settings.ocr_api_key,
        model=settings.ocr_model or DEFAULT_OCR_MODEL,
        timeout_seconds=settings.ocr_request_timeout_seconds,
    )
    try:
        response = provider.recognize(
            OCRProviderRequest(
                task_id=task.id,
                material_type=material_type,
                mime_type=revision.mime_type,
                file_path=private_path(settings.storage_root, revision.storage_path),
                file_name=document.original_file_name,
                uploaded_at=document.uploaded_at.isoformat(),
                file_hash=revision.file_hash,
            )
        )
    except OCRProviderError as error:
        service.fail_synchronously(
            task,
            category=error.category,
            code=error.code,
            message=error.safe_message,
            retryable=error.retryable,
        )
        raise BusinessError(
            error.code,
            error.safe_message,
            504 if error.category == "timeout" else 503,
            details={"retryable": error.retryable},
        ) from error
    try:
        draft, fields = validate_provider_payload(material_type, dict(response.payload))
    except ValidationError as error:
        service.fail_synchronously(
            task,
            category="response_format",
            code="OCR_SCHEMA_INVALID",
            message="OCR response did not match the material schema.",
            retryable=True,
        )
        raise BusinessError(
            "OCR_SCHEMA_INVALID",
            "OCR response did not match the material schema.",
            503,
            details={"retryable": True},
        ) from error
    result = service.complete_synchronously(
        task,
        raw_response=response.raw_response,
        draft=draft,
        fields=fields,
        result_source=response.source,
    )
    return success(
        request,
        _recognize_response(service, task, result, document.original_file_name),
    )


def _recognize_response(service, task, result, original_file_name: str) -> dict:
    fields = service.repository.fields(result.id)
    evidence = [
        {
            "path": field.field_path,
            "source_text": field.source_text,
            "value": field.parsed_value,
            "confidence": field.confidence,
            "uncertainty_reason": field.uncertainty_reason,
            "source_region": field.source_region,
        }
        for field in fields
    ]
    flat_payload = _normalize_algorithm_payload(
        {"draft": result.validated_draft, "fields": evidence},
        original_file_name,
    )
    flat = OCRRecognizeData.model_validate(flat_payload).model_dump(mode="json")
    return {
        **flat,
        "task_id": task.id,
        "result_id": result.id,
        "document_id": task.document_id,
        "document_revision_id": task.document_revision_id,
        "material_type": task.material_type,
        "status": task.status,
        "result_source": task.result_source,
        "draft": result.validated_draft,
    }


def _normalize_algorithm_payload(payload: dict, original_file_name: str) -> dict:
    """Accept the algorithm's documented flat result and the legacy worker envelope."""
    if isinstance(payload.get("draft"), dict):
        draft = payload["draft"]
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
            "evidence": payload.get("fields"),
        }
    payload.setdefault("original_file_name", original_file_name)
    return payload


class CreateOCRTaskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    document_id: str
    document_revision_id: str


class LabConfirmationItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_index: int | None = Field(default=None, ge=0)
    name: str | None = None
    value: str | int | float | None = None
    unit: str | None = None
    reference_range: str | None = None
    sample_date: str | None = None
    exam_date: str | None = None
    report_date: str | None = None
    visit_date: str | None = None
    note: str | None = Field(default=None, max_length=1000)


class ConfirmLabRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    result_id: str
    expected_revision_id: str
    visit_id: str | None = Field(default=None, max_length=100)
    sample_date: str | None = None
    exam_date: str | None = None
    report_date: str | None = None
    visit_date: str | None = None
    items: list[LabConfirmationItem] = Field(max_length=200)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_ocr_task(
    payload: CreateOCRTaskRequest,
    request: Request,
    service: OCRTaskServiceDependency,
) -> dict:
    task, created = service.create(payload.document_id, payload.document_revision_id)
    return success(request, {**task_data(task), "reused": not created})


@router.get("/{task_id}")
def get_ocr_task(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    return success(request, task_data(service.owned(task_id)))


@router.get("/{task_id}/result")
def get_ocr_result(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    return success(request, service.result(service.owned(task_id)))


@router.post("/{task_id}/confirm")
def confirm_ocr_lab(
    task_id: str,
    payload: ConfirmLabRequest | ClinicalTextConfirmRequest | MedicalOrderConfirmation,
    request: Request,
    lab_service: OCRTaskServiceDependency,
    clinical_service: ClinicalTextConfirmationServiceDependency,
    order_service: MedicalOrderServiceDependency,
) -> dict:
    if isinstance(payload, ClinicalTextConfirmRequest):
        return success(request, clinical_service.confirm(task_id, payload))
    if isinstance(payload, MedicalOrderConfirmation):
        orders, created = order_service.confirm(task_id, payload)
        return success(
            request,
            {
                "items": [medical_order_data(order) for order in orders],
                "reused": not created,
                "p0_evaluation": medical_order_p0(orders),
            },
        )
    return success(
        request,
        lab_service.confirm_lab(task_id, payload.model_dump(mode="json")),
    )


@router.post("/{task_id}/retry", status_code=status.HTTP_201_CREATED)
def retry_ocr_task(task_id: str, request: Request, service: OCRTaskServiceDependency) -> dict:
    task, created = service.retry(task_id)
    return success(request, {**task_data(task), "reused": not created})
