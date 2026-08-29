"""Authenticated OCR task API; processing is delegated to a separate worker."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, File, Form, Header, Request, UploadFile, status
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
from pomi_backend.db.models import OCRFieldResult, OCRResult, OCRTask
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import DocumentRepository, OCRRepository
from pomi_backend.schemas.clinical_text import ClinicalTextConfirmRequest
from pomi_backend.schemas.ocr_recognize import OCRRecognizeData, OCRResultConfirmRequest
from pomi_backend.schemas.orders import MedicalOrderConfirmation
from pomi_backend.services.document_storage import private_path
from pomi_backend.services.documents import DocumentService
from pomi_backend.services.ocr import (
    deduplication_key,
    normalize_algorithm_payload,
    sync_result_data,
    task_data,
)
from pomi_backend.services.ocr_provider import (
    OCRProviderError,
    OCRProviderRequest,
    Qwen3VLOCRProvider,
)
from pomi_backend.services.orders import medical_order_data, medical_order_p0
from pomi_backend.services.watermarks import (
    display_asset_data,
    generate_watermark_after_ocr,
)

router = APIRouter(prefix="/api/ocr/tasks", tags=["ocr"])

sync_router = APIRouter(prefix="/api/ocr", tags=["ocr"])


@sync_router.post("/results/{result_id}/confirm")
def confirm_sync_result(
    result_id: str,
    payload: OCRResultConfirmRequest,
    request: Request,
    service: OCRTaskServiceDependency,
) -> dict:
    return success(request, service.confirm_result(result_id, payload))


@sync_router.post("/recognize")
def recognize(
    request: Request,
    session: DatabaseSession,
    account: CurrentAccount,
    file: Annotated[UploadFile, File()],
    material_type: Annotated[str, Form()] = "outpatient_record",
    prompt_version: Annotated[str, Form()] = "pomi-ocr-v1",
    idempotency_key: Annotated[str, Header(alias="Idempotency-Key")] = "",
    consent_version: Annotated[
        str | None, Header(alias="X-External-Processing-Consent-Version")
    ] = None,
) -> dict:
    # 移除“门诊病历(outpatient_record)”支持，确保不接受该材料类型
    allowed = {"lab_report", "medical_order", "imaging_text_report"}
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
    document_service = DocumentService(session, account, settings.storage_root)
    document = document_service.upload(
        file,
        document_type=material_type,
        idempotency_key=idempotency_key,
        processing_notice_version=consent_version,
    )
    patient_id = document_service.patient.patient_id
    revision = DocumentRepository(session, patient_id).revision(
        document.id, document.current_revision_id
    )
    if revision is None:
        raise BusinessError("OCR_FILE_NOT_FOUND", "The uploaded file is unavailable.", 404)
    repository = OCRRepository(session, patient_id)
    scoped_key = deduplication_key(account.uid, idempotency_key)
    existing = repository.by_deduplication_key(scoped_key)
    if existing is not None:
        existing_result = repository.result(existing.id)
        if existing_result is None:
            raise BusinessError("OCR_RESULT_NOT_READY", "OCR result is not ready.", 409)
        display_asset = generate_watermark_after_ocr(
            session,
            settings.storage_root,
            document,
            revision,
        )
        return success(
            request,
            {
                **sync_result_data(existing, existing_result),
                "display_asset": display_asset_data(display_asset),
            },
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
                task_id=scoped_key,
                material_type=material_type,
                mime_type=revision.mime_type,
                file_path=private_path(settings.storage_root, revision.storage_path),
                file_name=document.original_file_name,
                uploaded_at=document.uploaded_at.isoformat(),
                file_hash=revision.file_hash,
            )
        )
    except OCRProviderError as error:
        raise BusinessError(
            error.code,
            error.safe_message,
            504 if error.category == "timeout" else 503,
            details={"retryable": error.retryable},
        ) from error
    parsed = OCRRecognizeData.model_validate(
        normalize_algorithm_payload(dict(response.payload), document.original_file_name)
    )
    task = OCRTask(
        id=new_uuid(),
        patient_id=patient_id,
        requested_by_uid=account.uid,
        document_id=document.id,
        document_revision_id=revision.id,
        material_type=material_type,
        status="pending_confirmation",
        model_name=settings.ocr_model or DEFAULT_OCR_MODEL,
        prompt_version=prompt_version,
        schema_version="pomi-ocr-schema-v1",
        deduplication_key=scoped_key,
        result_source=response.source,
    )
    draft = parsed.model_dump(mode="json", exclude={"ocr_task_id", "ocr_result_id"})
    result = OCRResult(
        id=new_uuid(),
        task_id=task.id,
        raw_response=response.raw_response,
        validated_draft=draft,
    )
    session.add(task)
    session.flush()
    session.add(result)
    session.flush()
    for field in parsed.evidence or []:
        if isinstance(field, dict) and field.get("path"):
            session.add(
                OCRFieldResult(
                    id=new_uuid(),
                    result_id=result.id,
                    field_path=str(field["path"]),
                    source_text=field.get("source_text"),
                    parsed_value=field.get("value"),
                    confidence=float(field.get("confidence", 0.0)),
                    uncertainty_reason=field.get("uncertainty_reason"),
                    source_region=field.get("source_region"),
                )
            )
    session.commit()
    display_asset = generate_watermark_after_ocr(
        session,
        settings.storage_root,
        document,
        revision,
    )
    return success(
        request,
        {
            **sync_result_data(task, result),
            "display_asset": display_asset_data(display_asset),
        },
    )


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
