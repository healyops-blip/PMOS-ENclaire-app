"""Single-process OCR worker with recoverable SQLite leases."""

from __future__ import annotations

import argparse
import hashlib
import logging
import socket
import time
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from jsonschema import ValidationError
from sqlalchemy.orm import Session, sessionmaker

from pomi_backend.config import Settings
from pomi_backend.db import build_engine, build_session_factory
from pomi_backend.db.models import Document, DocumentRevision, OCRFieldResult, OCRResult, OCRTask
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import OCRRepository
from pomi_backend.services.document_storage import private_path
from pomi_backend.services.ocr_provider import (
    OCRProvider,
    OCRProviderError,
    OCRProviderRequest,
    Qwen3VLOCRProvider,
)
from pomi_backend.services.ocr_validation import validate_provider_payload

logger = logging.getLogger("pomi.ocr.worker")


class OCRWorker:
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        *,
        storage_root: Path,
        provider: OCRProvider,
        worker_id: str,
        lease_seconds: int = 180,
    ) -> None:
        self.session_factory = session_factory
        self.storage_root = storage_root
        self.provider = provider
        self.worker_id = worker_id
        self.lease_seconds = lease_seconds

    def run_once(self) -> bool:
        now = utc_now()
        with self.session_factory() as session:
            repository = OCRRepository(session)
            repository.expire_ambiguous_calls(now=now)
            task = repository.claim(
                worker_id=self.worker_id,
                now=now,
                lease_seconds=self.lease_seconds,
            )
            task_id = task.id if task is not None else None
        if task_id is None:
            return False
        self._process(task_id)
        return True

    def _process(self, task_id: str) -> None:
        with self.session_factory() as session:
            task = session.get(OCRTask, task_id)
            if task is None or task.status != "processing" or task.lease_owner != self.worker_id:
                return
            repository = OCRRepository(session)
            result = repository.result(task.id)
            if result is not None:
                self._complete_existing(session, task, result)
                return
            document = session.get(Document, task.document_id)
            revision = session.get(DocumentRevision, task.document_revision_id)
            if (
                document is None
                or revision is None
                or revision.document_id != task.document_id
                or document.patient_id != task.patient_id
                or document.deleted_at is not None
            ):
                self._finish_error(
                    session,
                    task,
                    category="file",
                    code="OCR_FILE_NOT_FOUND",
                    message="The referenced document revision is unavailable.",
                )
                return
            try:
                path = private_path(self.storage_root, revision.storage_path)
            except Exception:
                self._finish_error(
                    session,
                    task,
                    category="file",
                    code="OCR_FILE_NOT_FOUND",
                    message="The referenced document file is unavailable.",
                )
                return
            task.provider_attempts += 1
            task.provider_call_started_at = utc_now()
            provider_call_started_at = task.provider_call_started_at
            task.attempt_history = [
                *task.attempt_history,
                {
                    "provider_attempt": task.provider_attempts,
                    "started_at": task.provider_call_started_at.isoformat(),
                    "status": "started",
                },
            ]
            session.commit()
            request = OCRProviderRequest(
                task_id=task.id,
                material_type=task.material_type,
                mime_type=revision.mime_type,
                file_path=path,
                file_name=document.original_file_name,
                uploaded_at=document.uploaded_at.isoformat(),
                file_hash=revision.file_hash,
            )
            try:
                response = self.provider.recognize(request)
                draft, fields = validate_provider_payload(
                    task.material_type,
                    response.payload,
                )
            except OCRProviderError as error:
                if not self._guard_provider_completion(
                    session, repository, task, provider_call_started_at
                ):
                    return
                self._handle_error(
                    session,
                    task,
                    category=error.category,
                    code=error.code,
                    message=error.safe_message,
                    retryable=error.retryable,
                )
                return
            except ValidationError:
                if not self._guard_provider_completion(
                    session, repository, task, provider_call_started_at
                ):
                    return
                self._handle_error(
                    session,
                    task,
                    category="response_format",
                    code="OCR_SCHEMA_INVALID",
                    message="OCR response did not match the material schema.",
                    retryable=True,
                )
                return
            except (OSError, ValueError):
                if not self._guard_provider_completion(
                    session, repository, task, provider_call_started_at
                ):
                    return
                self._finish_error(
                    session,
                    task,
                    category="file",
                    code="OCR_FILE_INVALID",
                    message="The document file could not be processed.",
                )
                return
            if not self._guard_provider_completion(
                session, repository, task, provider_call_started_at
            ):
                return
            result = OCRResult(
                id=new_uuid(),
                task_id=task.id,
                raw_response=response.raw_response,
                validated_draft=draft,
            )
            session.add(result)
            session.flush()
            session.add_all(
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
                    for field in fields
                ]
            )
            now = utc_now()
            task.status = "pending_confirmation"
            task.result_source = response.source
            task.error_category = None
            task.error_code = None
            task.error_message = None
            task.finished_at = now
            task.duration_ms = _duration_ms(task, now)
            task.lease_owner = None
            task.lease_expires_at = None
            task.provider_call_started_at = None
            task.attempt_history = _finish_history(task, "succeeded", now)
            task.updated_at = now
            session.commit()
            self._log(task, "pending_confirmation")

    def _guard_provider_completion(
        self,
        session: Session,
        repository: OCRRepository,
        task: OCRTask,
        provider_call_started_at: datetime,
    ) -> bool:
        if repository.guard_completion(
            task_id=task.id,
            worker_id=self.worker_id,
            provider_call_started_at=provider_call_started_at,
            now=utc_now(),
        ):
            return True
        session.rollback()
        logger.warning(
            "request_id=%s task_id=%s status=discarded_stale_provider_response",
            task.id,
            task.id,
        )
        return False

    def _handle_error(
        self,
        session: Session,
        task: OCRTask,
        *,
        category: str,
        code: str,
        message: str,
        retryable: bool,
    ) -> None:
        max_retries = 1 if category == "response_format" else 2
        category_failures = sum(
            1
            for attempt in task.attempt_history
            if attempt.get("status") == "failed" and attempt.get("category") == category
        )
        if retryable and category_failures < max_retries:
            now = utc_now()
            task.status = "queued"
            task.available_at = now + timedelta(seconds=min(2**task.provider_attempts, 30))
            task.lease_owner = None
            task.lease_expires_at = None
            task.provider_call_started_at = None
            task.error_category = category
            task.error_code = code
            task.error_message = message
            task.attempt_history = _finish_history(task, "failed", now, category, code)
            task.updated_at = now
            session.commit()
            self._log(task, "queued")
            return
        status = "timed_out" if category == "timeout" else "failed"
        self._finish_error(
            session, task, category=category, code=code, message=message, status=status
        )

    def _finish_error(
        self,
        session: Session,
        task: OCRTask,
        *,
        category: str,
        code: str,
        message: str,
        status: str = "failed",
    ) -> None:
        now = utc_now()
        task.status = status
        task.error_category = category
        task.error_code = code
        task.error_message = message[:500]
        task.finished_at = now
        task.duration_ms = _duration_ms(task, now)
        task.lease_owner = None
        task.lease_expires_at = None
        task.provider_call_started_at = None
        task.attempt_history = _finish_history(task, "failed", now, category, code)
        task.updated_at = now
        session.commit()
        self._log(task, status)

    def _complete_existing(self, session: Session, task: OCRTask, result: OCRResult) -> None:
        now = utc_now()
        task.status = "pending_confirmation"
        task.finished_at = task.finished_at or now
        task.duration_ms = task.duration_ms or _duration_ms(task, now)
        task.lease_owner = None
        task.lease_expires_at = None
        task.provider_call_started_at = None
        task.updated_at = now
        session.commit()

    def _log(self, task: OCRTask, status: str) -> None:
        uid_digest = hashlib.sha256(task.requested_by_uid.encode()).hexdigest()[:12]
        logger.info(
            "request_id=%s uid=%s task_id=%s document_id=%s status=%s "
            "error_category=%s duration_ms=%s",
            task.id,
            uid_digest,
            task.id,
            task.document_id,
            status,
            task.error_category,
            task.duration_ms,
        )


def _finish_history(
    task: OCRTask,
    status: str,
    now: Any,
    category: str | None = None,
    code: str | None = None,
) -> list[dict[str, Any]]:
    history = list(task.attempt_history)
    if history and history[-1].get("status") == "started":
        history[-1] = {
            **history[-1],
            "status": status,
            "finished_at": now.isoformat(),
            "category": category,
            "code": code,
        }
    return history


def _duration_ms(task: OCRTask, now: Any) -> int | None:
    return int((now - task.started_at).total_seconds() * 1000) if task.started_at else None


def build_worker(settings: Settings | None = None) -> OCRWorker:
    active = settings or Settings.from_env()
    if active.ocr_lease_seconds < active.ocr_request_timeout_seconds + 30:
        raise ValueError("POMI_OCR_LEASE_SECONDS must be at least timeout + 30 seconds")
    if not active.ocr_api_key:
        raise ValueError("POMI_OCR_API_KEY is required to start the OCR worker")
    engine = build_engine(active.database_url)
    provider = Qwen3VLOCRProvider(
        api_base_url=active.ocr_api_base_url,
        api_key=active.ocr_api_key,
        model=active.ocr_model,
        timeout_seconds=active.ocr_request_timeout_seconds,
    )
    worker_id = f"{socket.gethostname()}-{uuid.uuid4().hex[:8]}"
    return OCRWorker(
        build_session_factory(engine),
        storage_root=active.storage_root,
        provider=provider,
        worker_id=worker_id,
        lease_seconds=active.ocr_lease_seconds,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Pomi OCR worker")
    parser.add_argument("--once", action="store_true", help="Process at most one task")
    parser.add_argument("--poll-seconds", type=float, default=1.0)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    worker = build_worker()
    if args.once:
        worker.run_once()
        return
    while True:
        if not worker.run_once():
            time.sleep(max(args.poll_seconds, 0.1))


if __name__ == "__main__":
    main()
