"""Lease-based OCR worker that never writes unconfirmed formal data."""

from __future__ import annotations

import logging
import os
import socket
from datetime import timedelta
from time import monotonic

from sqlalchemy import or_, select
from sqlalchemy.orm import Session, sessionmaker

from pomi_backend.api.business import BusinessError
from pomi_backend.config import Settings
from pomi_backend.db.models import Document, DocumentRevision, OcrFieldResult, OcrResult, OcrTask
from pomi_backend.db.models.auth import utc_now
from pomi_backend.integrations.document_understanding import provider_for
from pomi_backend.services.document_storage import private_path
from pomi_backend.services.ocr import flatten_fields, validate_draft

logger = logging.getLogger("pomi.ocr_worker")
WORKER_ID = f"{socket.gethostname()}:{os.getpid()}"


def acquire_task(session: Session, settings: Settings) -> OcrTask | None:
    now = utc_now()
    task = session.scalar(
        select(OcrTask)
        .where(
            or_(
                OcrTask.task_status == "pending",
                (OcrTask.task_status == "processing") & (OcrTask.lease_expires_at < now),
            )
        )
        .order_by(OcrTask.queued_at)
        .limit(1)
    )
    if task is None:
        return None
    task.task_status = "processing"
    task.lease_owner = WORKER_ID
    task.lease_expires_at = now + timedelta(seconds=settings.ocr_lease_seconds)
    task.started_at = task.started_at or now
    task.attempt_count += 1
    task.error_code = None
    task.error_message = None
    task.progress = 10
    session.commit()
    session.refresh(task)
    return task


def run_ocr_once(factory: sessionmaker[Session], settings: Settings) -> bool:
    with factory() as session:
        task = acquire_task(session, settings)
        if task is None:
            return False
        task_id = task.id
    started = monotonic()
    try:
        with factory() as session:
            task = session.get(OcrTask, task_id)
            if task is None:
                return True
            document = session.get(Document, task.document_id)
            revision = session.get(DocumentRevision, task.document_revision_id)
            if document is None or revision is None:
                raise BusinessError("RESOURCE_NOT_FOUND", "OCR source is missing.", 404)
            path = private_path(settings.storage_root, revision.storage_path)
            provider = provider_for(settings)
            value = provider.recognize(path, document.mime_type, task.document_type)
            validate_draft(task.document_type, value)

            existing = session.scalar(select(OcrResult).where(OcrResult.ocr_task_id == task.id))
            if existing is None:
                result = OcrResult(
                    ocr_task_id=task.id,
                    raw_response_json=value,
                    parsed_result_json=value,
                    validation_status="valid",
                )
                session.add(result)
                session.flush()
                for field_path, parsed_value in flatten_fields(value):
                    session.add(
                        OcrFieldResult(
                            ocr_result_id=result.id,
                            field_path=field_path,
                            raw_text=None if parsed_value is None else str(parsed_value),
                            parsed_value=parsed_value,
                        )
                    )
            task.task_status = "fallback" if provider.result_source == "fallback" else "succeeded"
            task.result_source = provider.result_source
            task.finished_at = utc_now()
            task.processing_ms = round((monotonic() - started) * 1000)
            task.progress = 100
            task.lease_owner = None
            task.lease_expires_at = None
            document.upload_status = "ready"
            session.commit()
    except Exception as exc:
        logger.exception("OCR task failed", extra={"task_id": task_id})
        with factory() as session:
            task = session.get(OcrTask, task_id)
            if task is not None:
                code = exc.code if isinstance(exc, BusinessError) else "OCR_PROCESSING_FAILED"
                retryable = code in {
                    "MODEL_TIMEOUT",
                    "INVALID_MODEL_JSON",
                    "OCR_PROCESSING_FAILED",
                }
                task.task_status = (
                    "pending" if retryable and task.attempt_count < task.max_attempts else "failed"
                )
                task.error_code = code
                task.error_message = (
                    exc.message if isinstance(exc, BusinessError) else "OCR processing failed."
                )
                task.finished_at = utc_now() if task.task_status == "failed" else None
                task.lease_owner = None
                task.lease_expires_at = None
                session.commit()
    return True
